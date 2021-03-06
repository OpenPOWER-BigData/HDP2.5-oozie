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

package org.apache.oozie.action.hadoop;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.StringWriter;
import java.util.Arrays;
import java.util.Collection;
import java.util.Map;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.util.Shell;
import org.apache.commons.lang.StringUtils;
import org.apache.hadoop.mapred.JobConf;

public abstract class LauncherMain {

    public static final String HADOOP_JOBS = "hadoopJobs";
    public static final String MAPREDUCE_JOB_TAGS = "mapreduce.job.tags";
    static String[] HADOOP_SITE_FILES = new String[] {"core-site.xml", "hdfs-site.xml", "mapred-site.xml", "yarn-site.xml"};

    protected static void run(Class<? extends LauncherMain> klass, String[] args) throws Exception {
        LauncherMain main = klass.newInstance();
        main.run(args);
    }

    protected static Properties getHadoopJobIds(String logFile, Pattern[] patterns) throws IOException {
        Properties props = new Properties();
        StringBuffer sb = new StringBuffer(100);
        if (!new File(logFile).exists()) {
            System.err.println("Log file: " + logFile + "  not present. Therefore no Hadoop jobids found");
            props.setProperty(HADOOP_JOBS, "");
        }
        else {
            BufferedReader br = new BufferedReader(new FileReader(logFile));
            String line = br.readLine();
            String separator = "";
            while (line != null) {
                for (Pattern pattern : patterns) {
                    Matcher matcher = pattern.matcher(line);
                    if (matcher.find()) {
                        String jobId = matcher.group(1);
                        if (StringUtils.isEmpty(jobId) || jobId.equalsIgnoreCase("NULL")) {
                            continue;
                        }
                        jobId = jobId.replaceAll("application","job");
                        if (!sb.toString().contains(jobId)) {
                            sb.append(separator).append(jobId);
                        }
                        separator = ",";
                    }
                }
                line = br.readLine();
            }
            br.close();
            props.setProperty(HADOOP_JOBS, sb.toString());
        }
        return props;
    }

    protected static void writeExternalChildIDs(String logFile, Pattern[] patterns, String name) {
        // Harvesting and recording Hadoop Job IDs
        // See JavaActionExecutor#readExternalChildIDs for how they are read
        try {
            Properties jobIds = getHadoopJobIds(logFile, patterns);
            File file = new File(System.getProperty(LauncherMapper.ACTION_PREFIX
                    + LauncherMapper.ACTION_DATA_OUTPUT_PROPS));
            File externalChildIdsFile = new File(System.getProperty(LauncherMapper.ACTION_PREFIX
                    + LauncherMapper.ACTION_DATA_EXTERNAL_CHILD_IDS));
            OutputStream os = new FileOutputStream(file);
            OutputStream externalChildIdsStream = new FileOutputStream(externalChildIdsFile);
            try {
                jobIds.store(os, "");
                externalChildIdsStream.write(jobIds.getProperty(LauncherMain.HADOOP_JOBS).getBytes());
            }
            finally {
                os.close();
                externalChildIdsStream.close();
            }
            System.out.println(" Hadoop Job IDs executed by " + name + ": " + jobIds.getProperty(HADOOP_JOBS));
            System.out.println();
        }
        catch (Exception e) {
            System.out.println("WARN: Error getting Hadoop Job IDs executed by " + name);
            e.printStackTrace(System.out);
        }
    }

    protected abstract void run(String[] args) throws Exception;

    /**
     * Write to STDOUT (the task log) the Configuration/Properties values. All properties that contain
     * any of the strings in the maskSet will be masked when writting it to STDOUT.
     *
     * @param header message for the beginning of the Configuration/Properties dump.
     * @param maskSet set with substrings of property names to mask.
     * @param conf Configuration/Properties object to dump to STDOUT
     * @throws IOException thrown if an IO error ocurred.
     */
    @SuppressWarnings("unchecked")
    protected static void logMasking(String header, Collection<String> maskSet, Iterable conf) throws IOException {
        StringWriter writer = new StringWriter();
        writer.write(header + "\n");
        writer.write("--------------------\n");
        for (Map.Entry entry : (Iterable<Map.Entry>) conf) {
            String name = (String) entry.getKey();
            String value = (String) entry.getValue();
            for (String mask : maskSet) {
                if (name.contains(mask)) {
                    value = "*MASKED*";
                }
            }
            writer.write(" " + name + " : " + value + "\n");
        }
        writer.write("--------------------\n");
        writer.close();
        System.out.println(writer.toString());
        System.out.flush();
    }

    /**
     * Get file path from the given environment
     */
    protected static String getFilePathFromEnv(String env) {
        String path = System.getenv(env);
        if (path != null && Shell.WINDOWS) {
            // In Windows, file paths are enclosed in \" so remove them here
            // to avoid path errors
            if (path.charAt(0) == '"') {
                path = path.substring(1);
            }
            if (path.charAt(path.length() - 1) == '"') {
                path = path.substring(0, path.length() - 1);
            }
        }
        return path;
    }

    /**
     * Will run the user specified OozieActionConfigurator subclass (if one is provided) to update the action configuration.
     *
     * @param actionConf The action configuration to update
     * @throws OozieActionConfiguratorException
     */
    protected static void runConfigClass(JobConf actionConf) throws OozieActionConfiguratorException {
        String configClass = System.getProperty(LauncherMapper.OOZIE_ACTION_CONFIG_CLASS);
        if (configClass != null) {
            try {
                Class<?> klass = Class.forName(configClass);
                Class<? extends OozieActionConfigurator> actionConfiguratorKlass = klass.asSubclass(OozieActionConfigurator.class);
                OozieActionConfigurator actionConfigurator = actionConfiguratorKlass.newInstance();
                actionConfigurator.configure(actionConf);
            } catch (ClassNotFoundException e) {
                throw new OozieActionConfiguratorException("An Exception occured while instantiating the action config class", e);
            } catch (InstantiationException e) {
                throw new OozieActionConfiguratorException("An Exception occured while instantiating the action config class", e);
            } catch (IllegalAccessException e) {
                throw new OozieActionConfiguratorException("An Exception occured while instantiating the action config class", e);
            }
        }
    }

    /**
     * Read action configuration passes through action xml file.
     *
     * @return action  Configuration
     * @throws IOException
     */
    public static Configuration loadActionConf() throws IOException {
        // loading action conf prepared by Oozie
        Configuration actionConf = new Configuration(false);

        String actionXml = System.getProperty("oozie.action.conf.xml");

        if (actionXml == null) {
            throw new RuntimeException("Missing Java System Property [oozie.action.conf.xml]");
        }
        if (!new File(actionXml).exists()) {
            throw new RuntimeException("Action Configuration XML file [" + actionXml + "] does not exist");
        }

        actionConf.addResource(new Path("file:///", actionXml));
        return actionConf;
    }

    protected static void setYarnTag(Configuration actionConf) {
        if(actionConf.get(LauncherMainHadoopUtils.CHILD_MAPREDUCE_JOB_TAGS) != null) {
            // in case the user set their own tags, appending the launcher tag.
            if(actionConf.get(MAPREDUCE_JOB_TAGS) != null) {
                actionConf.set(MAPREDUCE_JOB_TAGS, actionConf.get(MAPREDUCE_JOB_TAGS) + ","
                        + actionConf.get(LauncherMainHadoopUtils.CHILD_MAPREDUCE_JOB_TAGS));
            } else {
                actionConf.set(MAPREDUCE_JOB_TAGS, actionConf.get(LauncherMainHadoopUtils.CHILD_MAPREDUCE_JOB_TAGS));
            }
        }
    }

    /**
     * Utility method that copies the contents of the src file into all of the dst file(s).
     * It only requires reading the src file once.
     *
     * @param src The source file
     * @param dst The destination file(s)
     * @throws IOException
     */
    protected static void copyFileMultiplex(File src, File... dst) throws IOException {
        InputStream is = null;
        OutputStream[] osa = new OutputStream[dst.length];
        try {
            is = new FileInputStream(src);
            for (int i = 0; i < osa.length; i++) {
                osa[i] = new FileOutputStream(dst[i]);
            }
            byte[] buffer = new byte[4096];
            int read;
            while ((read = is.read(buffer)) > -1) {
                for (OutputStream os : osa) {
                    os.write(buffer, 0, read);
                }
            }
        } finally {
            if (is != null) {
                is.close();
            }
            for (OutputStream os : osa) {
                if (os != null) {
                    os.close();
                }
            }
        }
    }

    protected void writeHadoopConfig(String actionXml, File basrDir) throws IOException {
        File actionXmlFile = new File(actionXml);
        System.out.println("Copying " + actionXml + " to " + basrDir + "/" + Arrays.toString(HADOOP_SITE_FILES));
        basrDir.mkdirs();
        File[] dstFiles = new File[HADOOP_SITE_FILES.length];
        for (int i = 0; i < dstFiles.length; i++) {
            dstFiles[i] = new File(basrDir, HADOOP_SITE_FILES[i]);
        }
        copyFileMultiplex(actionXmlFile, dstFiles);
    }
}

class LauncherMainException extends Exception {
    private int errorCode;

    public LauncherMainException(int code) {
        errorCode = code;
    }

    int getErrorCode() {
        return errorCode;
    }
}
