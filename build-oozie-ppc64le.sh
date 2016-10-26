#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -x

OOZIE_VERSION="4.2.0.2.5.0.0-1245"
HADOOP_VERSION="2.7.3.2.5.0.0-1245"
HIVE_VERSION="1.2.1000.2.5.0.0-1245"
PIG_VERSION="0.16.0"
SPARK_VERSION="1.6.2.2.5.0.0-1245"
HBASE_VERSION="1.1.2.2.5.0.0-1245"
TEZ_VERSION="0.7.0.2.5.0.0-1245"
SQOOP_VERSION=1.4.7-SNAPSHOT

bin/mkdistro.sh  -DskipTests -Dhadoop.version=$HADOOP_VERSION -Phadoop-2 -Dhbase.version=$HBASE_VERSION -Dtez.version=$TEZ_VERSION -Dpig.version=$PIG_VERSION -Dsqoop.version=$SQOOP_VERSION -Dhive.version=$HIVE_VERSION -Dpig.classifier=h2
