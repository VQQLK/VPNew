@rem Gradle wrapper script для Windows
@rem Для полноценной работы сгенерируйте через:
@rem   gradle wrapper --gradle-version 8.6
@if "%DEBUG%"=="" @echo off
set APP_HOME=%~dp0
set CLASSPATH=%APP_HOME%gradle\wrapper\gradle-wrapper.jar
java -classpath "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %*
