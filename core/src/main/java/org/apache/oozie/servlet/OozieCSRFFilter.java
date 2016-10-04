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

package org.apache.oozie.servlet;

import org.apache.oozie.service.ConfigurationService;
import org.apache.oozie.util.XLog;

import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import java.io.IOException;

public class OozieCSRFFilter extends RestCsrfPreventionFilter {

    private static final XLog LOG = XLog.getLog(OozieCSRFFilter.class);
    private String csrfHeader;
    private String csrfIgnoreMethods;
    private String csrfBrowserAgents;
    private boolean isCSRFEnabled;

    @Override
    public void init(FilterConfig filterConfig) throws ServletException {
        isCSRFEnabled = ConfigurationService.getBoolean(ConfigurationService.CSRF_PROPERTY);
        csrfHeader = ConfigurationService.get(ConfigurationService.CSRF_HEADER);
        csrfIgnoreMethods = ConfigurationService.get(ConfigurationService.CSRF_IGNORE_METHODS);
        csrfBrowserAgents = ConfigurationService.get(ConfigurationService.CSRF_BROWSER_AGENTS);
        super.setHeaderName(csrfHeader);
        super.parseMethodsToIgnore(csrfIgnoreMethods);
        super.parseBrowserUserAgents(csrfBrowserAgents);
        LOG.info("Initialized Oozie cross-site request forgery (CSRF) protection with, "
                        + "headerName = {0}, methodsToIgnore = {1}, browserUserAgents = {2}, isCSRFEnabled = {3}",
                csrfHeader, csrfIgnoreMethods, csrfBrowserAgents, isCSRFEnabled);
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         final FilterChain chain) throws IOException, ServletException {
        LOG.debug("Oozie cross-site request forgery (CSRF) protection running with, "
                        + "headerName = {0}, methodsToIgnore = {1}, browserUserAgents = {2}, isCSRFEnabled = {3}",
                csrfHeader, csrfIgnoreMethods, csrfBrowserAgents, isCSRFEnabled);
        if (isCSRFEnabled) {
            super.doFilter(request, response, chain);
        } else {
            chain.doFilter(request, response);
        }
    }

    @Override
    public void destroy() {
        super.destroy();
    }
}