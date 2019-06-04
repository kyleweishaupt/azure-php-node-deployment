@if "%SCM_TRACE_LEVEL%" NEQ "4" @echo off

:: ----------------------
:: KUDU Deployment Script
:: 
:: Version: 0.1.0 
::
:: A custom deployment script for PHP & Node applications in the same repository.
:: Ensures composer and NPM are available and installs dependencies from both.
::
:: ----------------------

:: Prerequisites
:: -------------

:: Files to ignore syncing
SET DEPLOY_IGNORE_FILES=.git;.vscode;.hg;.deployment;deploy.cmd;composer.phar;composer.json;composer.lock;package.json;package-lock.json;node_modules;.editorconfig;.gitattributes;.travis.yml;phpunit.xml.dist;README.md;web.config.default;webpack.mix.js;assets;tests

:: PHP command
SET PHP_CMD=php

:: Verify node.js installed
where node 2>nul >nul
IF %ERRORLEVEL% NEQ 0 (
  echo Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment.
  goto error
)

:: Setup
:: -----

setlocal enabledelayedexpansion

SET ARTIFACTS=%~dp0%..\artifacts

IF NOT DEFINED DEPLOYMENT_SOURCE (
  SET DEPLOYMENT_SOURCE=%~dp0%.
)

IF NOT DEFINED DEPLOYMENT_TARGET (
  SET DEPLOYMENT_TARGET=%ARTIFACTS%\wwwroot
)

IF NOT DEFINED NEXT_MANIFEST_PATH (
  SET NEXT_MANIFEST_PATH=%ARTIFACTS%\manifest

  IF NOT DEFINED PREVIOUS_MANIFEST_PATH (
    SET PREVIOUS_MANIFEST_PATH=%ARTIFACTS%\manifest
  )
)

IF NOT DEFINED KUDU_SYNC_CMD (
  :: Install kudu sync
  echo Installing Kudu Sync
  call npm install kudusync -g --silent
  IF !ERRORLEVEL! NEQ 0 goto error

  :: Locally just running "kuduSync" would also work
  SET KUDU_SYNC_CMD=%appdata%\npm\kuduSync.cmd
)
goto Deployment

:: Utility Functions
:: -----------------

:SelectNodeVersion

IF DEFINED KUDU_SELECT_NODE_VERSION_CMD (
  :: The following are done only on Windows Azure Websites environment
  call %KUDU_SELECT_NODE_VERSION_CMD% "%DEPLOYMENT_SOURCE%" "%DEPLOYMENT_TARGET%" "%DEPLOYMENT_TEMP%"
  IF !ERRORLEVEL! NEQ 0 goto error

  IF EXIST "%DEPLOYMENT_TEMP%\__nodeVersion.tmp" (
    SET /p NODE_EXE=<"%DEPLOYMENT_TEMP%\__nodeVersion.tmp"
    IF !ERRORLEVEL! NEQ 0 goto error
  )
  
  IF EXIST "%DEPLOYMENT_TEMP%\__npmVersion.tmp" (
    SET /p NPM_JS_PATH=<"%DEPLOYMENT_TEMP%\__npmVersion.tmp"
    IF !ERRORLEVEL! NEQ 0 goto error
  )

  IF NOT DEFINED NODE_EXE (
    SET NODE_EXE=node
  )

  SET NPM_CMD="!NODE_EXE!" "!NPM_JS_PATH!"
) ELSE (
  SET NPM_CMD=npm
  SET NODE_EXE=node
)

goto :EOF

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Deployment
:: ----------

:Deployment
echo Starting deployment!

:: 1. Composer
IF EXIST "%DEPLOYMENT_SOURCE%\composer.json" (
  cd %DEPLOYMENT_SOURCE%

  IF NOT EXIST "%DEPLOYMENT_SOURCE%\composer.phar" (
    echo Composer.phar not found. Downloading...
    call curl -s https://getcomposer.org/installer | php
    IF !ERRORLEVEL! NEQ 0 goto error
  ) ELSE (
      echo Attempting to update composer.phar
      !PHP_CMD! composer.phar self-update
  )
  
  echo Running Composer install...
  call !PHP_CMD! composer.phar install --no-scripts --no-interaction --no-progress
  IF !ERRORLEVEL! NEQ 0 goto error

  echo Regenerating Composer optimized autoloader...
  call !PHP_CMD! composer.phar dumpautoload -o
  IF !ERRORLEVEL! NEQ 0 goto error
)

:: 2. Select node version
call :SelectNodeVersion

:: 3. Install npm packages
IF EXIST "%DEPLOYMENT_SOURCE%\package.json" (
  cd %DEPLOYMENT_SOURCE%
  echo Found package.json, running npm install...
  call :ExecuteCmd !NPM_CMD! install
  IF !ERRORLEVEL! NEQ 0 goto error
)

:: 4. Run build step
IF EXIST "%DEPLOYMENT_SOURCE%\package.json" (
  cd %DEPLOYMENT_SOURCE%
  echo Running npm production script...
  call :ExecuteCmd !NPM_CMD! run production
  IF !ERRORLEVEL! NEQ 0 goto error
)

:: Finally. KuduSync
IF /I "%IN_PLACE_DEPLOYMENT%" NEQ "1" (
  call :ExecuteCmd "%KUDU_SYNC_CMD%" -v 50 -f "%DEPLOYMENT_SOURCE%" -t "%DEPLOYMENT_TARGET%" -n "%NEXT_MANIFEST_PATH%" -p "%PREVIOUS_MANIFEST_PATH%" -i "%DEPLOY_IGNORE_FILES%"
  IF !ERRORLEVEL! NEQ 0 goto error
)

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
goto end

:: Execute command routine that will echo out when error
:ExecuteCmd
setlocal
set _CMD_=%*
call %_CMD_%
if "%ERRORLEVEL%" NEQ "0" echo Failed exitCode=%ERRORLEVEL%, command=%_CMD_%
exit /b %ERRORLEVEL%

:error
endlocal
echo An error has occurred during web site deployment.
call :exitSetErrorLevel
call :exitFromFunction 2>nul

:exitSetErrorLevel
exit /b 1

:exitFromFunction
()

:end
endlocal
echo Finished successfully!
