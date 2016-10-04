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
package org.apache.oozie.command;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileStatus;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.FileUtil;
import org.apache.hadoop.fs.Path;
import org.apache.oozie.ErrorCode;
import org.apache.oozie.service.HadoopAccessorException;
import org.apache.oozie.service.HadoopAccessorService;
import org.apache.oozie.service.Services;
import org.apache.oozie.service.XLogCopyService;
import org.apache.oozie.util.XLog;

import java.io.IOException;
import java.net.URI;
import java.util.List;
public class XLogPurgeXCommand extends XCommand<Void> {
    private List<String> wfList;
    private List<String> coordList;
    private List<String> bundleList;

    public XLogPurgeXCommand(List<String> wfList, List<String> coordList, List<String> bundleList) {
        super("XLogPurge", "XLogPurge", 0);
        this.wfList = wfList;
        this.coordList = coordList;
        this.bundleList = bundleList;
    }


    /* (non-Javadoc)
     * @see org.apache.oozie.command.XCommand#execute()
     */
    @Override
    protected Void execute() throws CommandException {
        XLogCopyService xls = Services.get().get(XLogCopyService.class);
        String hdfsDir = xls.getConfHdfsLogDir();

        XLog.Info.get().clear();
        XLog log = XLog.getLog(getClass());
        HadoopAccessorService has = Services.get().get(HadoopAccessorService.class);
        URI uri = new Path(hdfsDir).toUri();
        Configuration fsConf = has.createJobConf(uri.getAuthority());
        FileSystem fs = null;

        try {
            fs = has.createFileSystem(System.getProperty("user.name"), uri, fsConf);
        }
        catch (Exception ex) {
            log.error("user has to be specified to access hdfs",
                    new HadoopAccessorException(ErrorCode.E0902, "user has to be specified to access FileSystem"));
        }

        deleteJobLogs(fs, hdfsDir, wfList);
        deleteJobLogs(fs, hdfsDir, coordList);
        deleteJobLogs(fs, hdfsDir, bundleList);

        try {
            fs.close();
        }
        catch (IOException ex) {
            LOG.error("cannot close filesystem");
        }
        return null;
    }

    private void deleteJobLogs(FileSystem fs, String hdfsDir, List<String> jobIds) {
        Path[] paths = null;
        try {
            FileStatus[] fileStatuses = fs.listStatus(new Path(hdfsDir));
            paths = FileUtil.stat2Paths(fileStatuses);
        }
        catch (IOException ex) {
            LOG.error("file not found " + ex.getMessage());
        }

        for (Path path : paths) {
            for (String jobId : jobIds) {
                final Path p = new Path(path, jobId + ".log");
                try {
                    if (fs.exists(p)) {
                        fs.delete(p, true);
                    }
                }
                catch (IOException ex) {
                    LOG.error("cannot delete job logs in hdfs",
                        new HadoopAccessorException(ErrorCode.E0902, "cannot delete file " + p));
                }
            }
        }
    }

    /* (non-Javadoc)
    * @see org.apache.oozie.command.XCommand#loadState()
    */
    @Override
    protected void loadState() throws CommandException {
    }

    /* (non-Javadoc)
    * @see org.apache.oozie.command.XCommand#getEntityKey()
    */
    @Override
    public String getEntityKey() {
        return null;
    }

    /* (non-Javadoc)
     * @see org.apache.oozie.command.XCommand#isLockRequired()
     */
    @Override
    protected boolean isLockRequired() {
        return false;
    }

    /* (non-Javadoc)
     * @see org.apache.oozie.command.XCommand#verifyPrecondition()
     */
    @Override
    protected void verifyPrecondition() throws CommandException, PreconditionException {
    }
}
