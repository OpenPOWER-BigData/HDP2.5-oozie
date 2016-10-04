/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.oozie.service;

import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.conf.Configuration;
import org.apache.oozie.ErrorCode;
import org.apache.oozie.util.XLog;
import org.apache.oozie.util.XLogFilter;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.net.URI;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.SQLException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

/**
 * The XLogCopyService copies oozie.log contents onto HDFS. By default,
 * it runs every 5 minutes.
 */
public class XLogCopyService implements Service {

    public static final String CONF_PREFIX = Service.CONF_PREFIX + "XLogCopyService.";

    /**
     * Time interval, in minutes, at which the service will be scheduled to run.
     */
    public static final String CONF_SERVICE_INTERVAL = CONF_PREFIX + "interval";

    /**
     * HDFS directory where oozie log will be forward to.
     */
    public static final String CONF_HDFS_LOG_DIR = CONF_PREFIX + "hdfs.log.dir";

    public static final String CONF_LOG_PURGE = CONF_PREFIX + "purge.enable";

    public static String HDFS_LOG_DIR;

    public static int CURRENT_LINE_NUMBER = 0;

    public static String LAST_COMPLETE_LOG_FILE_NAME = "oozie.log";

    public static String OOZIE_INSTANCE_ID = "";

    public static HashMap<String, String> jdbcConf = new HashMap<String, String>();

    public static String LOGPROGRESS_GET_QUERY = "select data from OOZIE_SYS where name = '";

    public static String LOGPROGRESS_UPDATE_QUERY = "update OOZIE_SYS set data = '";

    public static String LOGPROGRESS_UPDATE_QUERY_WHERE_CLAUSE = "' where name = '";

    public static String LOGPROGRESS_INSERT_QUERY = "insert into OOZIE_SYS (name, data) values ";

    public static Boolean IS_LOG_PURGING_ENABLED = false;

    private final XLog log = XLog.getLog(getClass());

    static class XLogCopyRunnable implements Runnable {

        private final String hdfsDir;

        public XLogCopyRunnable(String hdfsDir) {
            this.hdfsDir = hdfsDir;
        }

        public void run() {
            XLogService xls = Services.get().get(XLogService.class);
            String oozieLogPath = xls.getOozieLogPath();
            String oozieLogName = xls.getOozieLogName();

            XLog.Info.get().clear();
            XLog log = XLog.getLog(getClass());
            log.info("hdfs log dir is " + hdfsDir);

            if (oozieLogPath != null && oozieLogName != null) {
                String[] children = new File(oozieLogPath).list();
                if (children != null) {
                    List<String> rolloveredFiles = new ArrayList<String>();
                    if (oozieLogName.equals(LAST_COMPLETE_LOG_FILE_NAME)) {
                        //This means no rollover has happened yet before this run.
                        for (String child: children) {
                            if (child.startsWith(oozieLogName) && !child.equals(oozieLogName)) {
                                rolloveredFiles.add(child);
                            }
                        }
                    }
                    else {
                        long lastFileModifyTime = new File(oozieLogPath, LAST_COMPLETE_LOG_FILE_NAME).lastModified();
                        for (String child: children) {
                            //Collect files that have been rolloverred.
                            if (!child.equals(oozieLogName) && child.startsWith(oozieLogName) &&
                                    lastFileModifyTime < getLastModifiedTime(oozieLogPath, child)) {
                                rolloveredFiles.add(child);
                            }
                        }
                    }

                    if (!rolloveredFiles.isEmpty()) {
                        String earliestFile = rolloveredFiles.get(0);
                        long earliestTime = getLastModifiedTime(oozieLogPath, earliestFile);
                        String latestFile = earliestFile;
                        long latestTime = earliestTime;
                        int earliestIndex = 0;
                        for (int i = 0; i < rolloveredFiles.size(); i++) {
                            String file = rolloveredFiles.get(i);
                            if (earliestTime > getLastModifiedTime(oozieLogPath, file)) {
                                earliestTime = getLastModifiedTime(oozieLogPath, file);
                                earliestFile = file;
                                earliestIndex = i;
                            }
                            if (latestTime < getLastModifiedTime(oozieLogPath, file)) {
                                latestTime = getLastModifiedTime(oozieLogPath, file);
                                latestFile = file;
                            }
                        }

                        rolloveredFiles.remove(earliestIndex);
                        //TODO
                        //Finish writing the file we processed last run
                        writeToHdfs(CURRENT_LINE_NUMBER, new File(oozieLogPath, earliestFile));

                        for (String file : rolloveredFiles) {
                            //Process all the rolloverred files in the middle if any
                            //Under normal conditions without interruption of services, this for loop should be empty
                            writeToHdfs(0, new File(oozieLogPath, file));
                        }

                        LAST_COMPLETE_LOG_FILE_NAME = latestFile;
                        //Process the new oozie.log file
                        CURRENT_LINE_NUMBER = writeToHdfs(0, new File(oozieLogPath, oozieLogName));
                    }
                    else {
                        //No rollovers since last run, continue processing the current oozie.log file
                        CURRENT_LINE_NUMBER = writeToHdfs(CURRENT_LINE_NUMBER, new File(oozieLogPath, oozieLogName));
                    }
                }
            }
            updateLogProgress(CURRENT_LINE_NUMBER + "," + LAST_COMPLETE_LOG_FILE_NAME);
        }

        private int writeToHdfs(int lineNumber, File file){
            XLog.Info.get().clear();
            XLog log = XLog.getLog(getClass());
            HadoopAccessorService has = Services.get().get(HadoopAccessorService.class);
            URI uri = new Path(hdfsDir).toUri();
            Configuration fsConf = has.createJobConf(uri.getAuthority());
            FileSystem fs = null;
            HashMap<String, StringBuilder> logMap = new HashMap<String, StringBuilder>();
            Pattern splitterPattern = XLogFilter.getSplitterPattern();

            try {
                BufferedReader br = new BufferedReader(new FileReader(file));
                String currentLine = "";
                Pattern pattern = Pattern.compile("JOB\\[(.*?)\\]");

                // Skip lines that have been copied already
                for (int i = 0; i < lineNumber; i++) {
                    br.readLine();
                }

                String jobId = "";
                while ((currentLine = br.readLine()) != null) {
                    Matcher splitter = splitterPattern.matcher(currentLine);
                    if (splitter.matches()){
                        jobId = "";
                        Matcher matcher = pattern.matcher(currentLine);
                        while (matcher.find()) {
                            jobId = matcher.group(1);
                            break;
                        }
                    }

                    //For efficiency purpose, we first store lines to be copied by jobId
                    if (!jobId.trim().equals("-") && !jobId.isEmpty()) {
                        StringBuilder sb = new StringBuilder();
                        if (logMap.containsKey(jobId)) {
                            sb = logMap.get(jobId);
                        }
                        sb.append(currentLine).append("\n");
                        logMap.put(jobId, sb);
                    }
                    lineNumber++;
                }

                br.close();

                try {
                    fs = has.createFileSystem(System.getProperty("user.name"), uri, fsConf);
                }
                catch (Exception ex) {
                    log.error("user has to be specified to access hdfs",
                            new HadoopAccessorException(ErrorCode.E0902, "user has to be specified to access FileSystem"));
                }

                for (String id : logMap.keySet()) {
                    final Path p = new Path(hdfsDir, id + ".log");
                    FSDataOutputStream os = null;
                    if (!fs.exists(p)) {
                        os = fs.create(p);
                    }
                    else {
                        os = fs.append(p);
                    }

                    BufferedWriter bw = new BufferedWriter( new OutputStreamWriter(os));
                    bw.write(logMap.get(id).toString());
                    bw.close();
                }

                fs.close();
            }
            catch (FileNotFoundException ex) {
                log.error(file + " does not exist",
                        new HadoopAccessorException(ErrorCode.E0902, "cannot locate file: " + file + " on hdfs"));
            }
            catch (IOException ex) {
                log.warn("log copy failed with exception: " + ex.getMessage());
            }

            return lineNumber;
        }
    }

    private static long getLastModifiedTime(String directory, String file) {
        return new File(directory, file).lastModified();
    }

    public void init(Services services) throws ServiceException{
        Configuration conf = services.getConf();
        int interval = conf.getInt(CONF_SERVICE_INTERVAL, 300);
        HDFS_LOG_DIR = conf.get(CONF_HDFS_LOG_DIR);
        if (HDFS_LOG_DIR == null || HDFS_LOG_DIR.isEmpty()) {
            throw new ServiceException(ErrorCode.E0307, "hdfs log directory not specified");
        }
        IS_LOG_PURGING_ENABLED = conf.getBoolean(CONF_LOG_PURGE, false);
        OOZIE_INSTANCE_ID = System.getenv("OOZIE_INSTANCE_ID");
        LOGPROGRESS_GET_QUERY +=  OOZIE_INSTANCE_ID + ".logprogress'";
        LOGPROGRESS_UPDATE_QUERY_WHERE_CLAUSE +=  OOZIE_INSTANCE_ID + ".logprogress'";
        LOGPROGRESS_INSERT_QUERY += "('" + OOZIE_INSTANCE_ID + ".logprogress', '"
                + CURRENT_LINE_NUMBER + "," + LAST_COMPLETE_LOG_FILE_NAME + "')";

        jdbcConf.put("driver", conf.get(JPAService.CONF_DRIVER));
        String url = conf.get(JPAService.CONF_URL);
        jdbcConf.put("url", url);
        jdbcConf.put("user", conf.get(JPAService.CONF_USERNAME));

        jdbcConf.put("password", services.get(HadoopAccessorService.class).getPasswordFromHadoopConf(conf,
                JPAService.CONF_PASSWORD));
        String dbType = url.substring("jdbc:".length());
        if (dbType.indexOf(":") <= 0) {
            throw new RuntimeException("Invalid JDBC URL, missing vendor 'jdbc:[VENDOR]:...'");
        }
        dbType = dbType.substring(0, dbType.indexOf(":"));
        jdbcConf.put("dbtype", dbType);

        initLogProgress();

        XLogCopyRunnable runnable = new XLogCopyRunnable(new Path(HDFS_LOG_DIR, OOZIE_INSTANCE_ID).toString());
        services.get(SchedulerService.class).schedule(runnable, 10, interval, SchedulerService.Unit.SEC);
        log.info("XLogCopyService is initialized");
    }

    @Override
    public Class<? extends Service> getInterface() {
        return XLogCopyService.class;
    }

    @Override
    public void destroy() {
        updateLogProgress(CURRENT_LINE_NUMBER + "," + LAST_COMPLETE_LOG_FILE_NAME);
    }

    public String getConfHdfsLogDir() {
        return HDFS_LOG_DIR;
    }

    private static void initLogProgress() throws ServiceException{
        String logProgress = "";
        XLog log = XLog.getLog(XLogCopyService.class);

        try {
            Class.forName(jdbcConf.get("driver")).newInstance();
            Connection conn = DriverManager.getConnection(jdbcConf.get("url"), jdbcConf.get("user"), jdbcConf.get("password"));
            try {
                log.info("execute query: " + LOGPROGRESS_GET_QUERY);
                Statement st = conn.createStatement();
                ResultSet rs = st.executeQuery(LOGPROGRESS_GET_QUERY);
                if (rs.next()) {
                    logProgress = rs.getString(1);
                }

                rs.close();
                st.close();
            }
            catch (SQLException ex) {
                throw new ServiceException(ErrorCode.E0170, "cannot query OOZIE_SYS table", ex);
            }
        }
        catch (SQLException ex) {
            throw new ServiceException(ErrorCode.E0600, ex);
        }
        catch (Exception ex) {
            throw new ServiceException(ErrorCode.E0307, ex);
        }

        if (!logProgress.isEmpty()) {
            String[] progressRecord = logProgress.trim().split(",");
            try {
                CURRENT_LINE_NUMBER = Integer.parseInt(progressRecord[0].trim());
            }
            catch (NumberFormatException ex) {
                log.warn("Can not retrieve line number from log progress file, default it to 0");
            }

            LAST_COMPLETE_LOG_FILE_NAME = progressRecord[1].trim();
        }
        else {
            try {
                Class.forName(jdbcConf.get("driver")).newInstance();
                Connection conn = DriverManager.getConnection(jdbcConf.get("url"), jdbcConf.get("user"), jdbcConf.get("password"));
                try {
                    log.info("insert query is " + LOGPROGRESS_INSERT_QUERY);
                    Statement st = conn.createStatement();
                    st.executeUpdate(LOGPROGRESS_INSERT_QUERY);
                    st.close();
                }
                catch (SQLException ex) {
                    throw new ServiceException(ErrorCode.E0170, "cannot insert into OOZIE_SYS table", ex);
                }
            }
            catch (SQLException ex) {
                throw new ServiceException(ErrorCode.E0600, ex);
            }
            catch (Exception ex) {
                throw new ServiceException(ErrorCode.E0307, ex);
            }
        }
    }

    private static void updateLogProgress(String logProgress) {
        XLog log = XLog.getLog(XLogCopyService.class);
        try {
            Class.forName(jdbcConf.get("driver")).newInstance();
            Connection conn = DriverManager.getConnection(jdbcConf.get("url"), jdbcConf.get("user"), jdbcConf.get("password"));
            try {
                String updateQuery = LOGPROGRESS_UPDATE_QUERY + logProgress + LOGPROGRESS_UPDATE_QUERY_WHERE_CLAUSE;
                log.info("execute query; " + updateQuery);
                Statement st = conn.createStatement();
                st.executeUpdate(updateQuery);
                st.close();
            }
            catch (SQLException ex) {
                log.error("Cannot update logProgress in OOZIE_SYS table: " + ex.getMessage());
            }
        }
        catch (Exception ex) {
            log.error("run time error " + ex.getMessage());
        }
    }
}
