#!/bin/bash -eu
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

mv $SRC/{*.zip,*.dict} $OUT

cat > patch.diff <<- EOM
diff --git a/pom.xml b/pom.xml
index 3e29db9..c79e086 100644
--- a/pom.xml	2022-04-14 17:14:14.830692400 +0200
+++ b/pom.xml	2022-04-14 17:33:25.535451222 +0200
@@ -30,6 +30,8 @@
 
  <properties>
   <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
+  <maven.compiler.source>1.8</maven.compiler.source>
+  <maven.compiler.target>1.8</maven.compiler.target>
  </properties>
 
  <dependencies>
@@ -56,19 +58,6 @@
       </goals>
      </execution>
     </executions>
-   </plugin>
-   <plugin>
-    <groupId>org.apache.maven.plugins</groupId>
-    <artifactId>maven-javadoc-plugin</artifactId>
-    <version>2.9.1</version>
-    <executions>
-     <execution>
-      <id>attach-javadocs</id>
-      <goals>
-       <goal>jar</goal>
-      </goals>
-     </execution>
-    </executions>
    </plugin>
   </plugins>
  </build>

EOM

git apply patch.diff


# Use standard apache structure
mkdir src/main
mv src/java src/main/
rm -r src/main/java/tests

MAVEN_ARGS="-Djavac.src.version=15 -Djavac.target.version=15 -DskipTests"
$MVN package $MAVEN_ARGS
CURRENT_VERSION=$($MVN org.apache.maven.plugins:maven-help-plugin:3.2.0:evaluate \
 -Dexpression=project.version -q -DforceStdout)
cp "target/xmlpull-$CURRENT_VERSION.jar" "$OUT/xmlpull.jar"

ALL_JARS="xmlpull.jar"

# The classpath at build-time includes the project jars in $OUT as well as the
# Jazzer API.
BUILD_CLASSPATH=$(echo $ALL_JARS | xargs printf -- "$OUT/%s:"):$JAZZER_API_PATH

# All .jar and .class files lie in the same directory as the fuzzer at runtime.
RUNTIME_CLASSPATH=$(echo $ALL_JARS | xargs printf -- "\$this_dir/%s:"):\$this_dir

for fuzzer in $(find $SRC -name '*Fuzzer.java'); do
  fuzzer_basename=$(basename -s .java $fuzzer)
  javac -cp $BUILD_CLASSPATH $fuzzer
  cp $SRC/$fuzzer_basename.class $OUT/

  # Create an execution wrapper that executes Jazzer with the correct arguments.
  echo "#!/bin/sh
# LLVMFuzzerTestOneInput for fuzzer detection.
this_dir=\$(dirname \"\$0\")
LD_LIBRARY_PATH=\"$JVM_LD_LIBRARY_PATH\":\$this_dir \
\$this_dir/jazzer_driver --agent_path=\$this_dir/jazzer_agent_deploy.jar \
--cp=$RUNTIME_CLASSPATH \
--target_class=$fuzzer_basename \
--jvm_args=\"-Xmx2048m\" \
\$@" > $OUT/$fuzzer_basename
  chmod u+x $OUT/$fuzzer_basename
done 