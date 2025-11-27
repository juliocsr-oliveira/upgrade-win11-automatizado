@echo off
setlocal enableextensions enabledelayedexpansion
chcp 65001 >nul

:: ==========================
:: CONFIGURAÇÕES GERAIS
:: ==========================
set "WORKDIR=C:\TempUpgradeW11"
set "ISOFILENAME=Win11.iso"
set "LOCALISO=%WORKDIR%\%ISOFILENAME%"
set "TMPDOWNLOAD=%LOCALISO%.download"
set "BAD_ISO_DIR=%WORKDIR%\InvalidISOs"
set "LOG_LOCAL=C:\LogsUpgradeW11"
set "NETWORK_LOG_SHARE=SERVER\Share"
set "ONEDRIVE_URL=https://example.com/windows.iso"
set "EXPECTED_HASH=REPLACE_WITH_SHA256"
set "MIN_SIZE=5200000000"
set "MAX_RETRIES=3"
set "LOCKFILE=%WORKDIR%\UpgradeInProgress.lock"
set "REBOOT_FLAG=%WORKDIR%\UpgradePendingReboot.flag"
set "COMPLETED_FLAG=%WORKDIR%\UpgradeCompleted.flag"

:: ==========================
:: CRIA PASTA TEMPORÁRIA E LOCKFILE
:: ==========================
set "TEMPPATH=C:\TempUpgrade"
if not exist "%TEMPPATH%" mkdir "%TEMPPATH%" >nul 2>&1

set "TEMPUPG=%TEMPPATH%\UpgradeTemp"
if not exist "%TEMPUPG%" mkdir "%TEMPUPG%" >nul 2>&1

:: Define o arquivo de log imediatamente
set "NETWORK_LOG_SHARE=\\SERVER\LogsUpgradeW11\%COMPUTERNAME%"
if exist "%NETWORK_LOG_SHARE%\" (
    set "LOGFILE=%NETWORK_LOG_SHARE%\%COMPUTERNAME%-UpgradeLog.log"
) else (
    set "LOGFILE=%TEMPPATH%\%COMPUTERNAME%-UpgradeLog.log"
)

set "LOCKFILE=%TEMPUPG%\UpgradeInProgress.lock"
if exist "%LOCKFILE%" (
    echo [!] Outro processo de upgrade já está em andamento. >> "%LOGFILE%"
    exit /b 1
)
echo %date% %time% > "%LOCKFILE%"
echo [%date% %time%] Lockfile criado com sucesso em "%LOCKFILE%" >> "%TEMPPATH%\UpgradeLog.log"

:: --- DEFINIR LOGFILE IMEDIATAMENTE (corrige fechamentos por >> "%LOGFILE%")
set "DESTINO_REDE=\\SERVER\LogsUpgradeW11"
set "PASTA_COMPUTADOR=%DESTINO_REDE%\%COMPUTERNAME%"
set "LOCAL_LOG_FOLDER=%TEMPPATH%\%COMPUTERNAME%"
set "MAX_TENTATIVAS=5"
set /a TENTATIVA=1

:TESTE_REDE
ping -n 1 \\SERVER\\ >nul 2>&1
if %errorlevel%==0 (
    if not exist "%PASTA_COMPUTADOR%" mkdir "%PASTA_COMPUTADOR%" >nul 2>&1
    if exist "%PASTA_COMPUTADOR%" (
        set "LOGFILE=%PASTA_COMPUTADOR%\%COMPUTERNAME%-UpgradeLog.log"
        echo [INFO] Rede acessível. Log definido em %LOGFILE%
        goto :LOG_INICIAL
    )
)

:: Se rede não acessível após tentativas
if %TENTATIVA% lss %MAX_TENTATIVAS% (
    echo [WARN] Falha ao acessar rede. Tentativa %TENTATIVA%/%MAX_TENTATIVAS%...
    set /a TENTATIVA+=1
    timeout /t 5 /nobreak >nul
    goto :TESTE_REDE
)

:: Rede inacessível, usa log local
if not exist "%LOCAL_LOG_FOLDER%" mkdir "%LOCAL_LOG_FOLDER%" >nul 2>&1
set "LOGFILE=%LOCAL_LOG_FOLDER%\%COMPUTERNAME%-UpgradeLog.log"
echo [ERRO] Rede inacessível. Log definido localmente em %LOGFILE%

:LOG_INICIAL
>> "%LOGFILE%" echo ==============================================
>> "%LOGFILE%" echo Início do log: %DATE% %TIME%
>> "%LOGFILE%" echo Lockfile: %LOCKFILE%
>> "%LOGFILE%" echo Log definido: %LOGFILE%
>> "%LOGFILE%" echo ==============================================

:: ==========================
:: COPIAR LOGS DO SETUP
:: ==========================
copy /y "C:\TempUpgradeLogs\setupact.log" "%LOCAL_LOG_FOLDER%\" >nul 2>&1
copy /y "C:\TempUpgradeLogs\setuperr.log" "%LOCAL_LOG_FOLDER%\" >nul 2>&1
echo [%date% %time%] Logs copiados da pasta C:\TempUpgradeLogs e armazenados em: %LOCAL_LOG_FOLDER% >> "%LOGFILE%"

:: ==========================================================
:: VERIFICAÇÃO SE O SISTEMA ESTÁ AGUARDANDO REINICIALIZAÇÃO DO UPGRADE
:: ==========================================================
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1

if %errorlevel%==0 (
    call :LogMessage "[ALERTA CRÍTICO] O sistema já concluiu o upgrade e está AGUARDANDO REINICIAR."
    call :LogMessage "Ação abortada para evitar destruição de arquivos necessários ao boot do Windows 11."
    call :LogMessage "SISTEMA JA MIGRADO (aguardando reboot). ENCERRANDO SCRIPT."
    exit /b 0
)

call :LogMessage "Nenhum sinal de migração concluída. Continuando normalmente..."

:: ==========================
:: REMOVER PASTAS RESIDUAIS (ANTES DE QUALQUER DOWNLOAD)
:: ==========================
call :LogMessage "Removendo pastas residuais antes do upgrade..."

call :RemoverPasta "C:\$WINDOWS.~BT"
call :RemoverPasta "C:\TempUpgradeW11\InvalidISOs"
call :RemoverPasta "C:\Windows10Upgrade"
call :RemoverPasta "C:\$WINDOWS.~WS"

call :LogMessage "Limpeza de pastas finalizada com sucesso."
call :LogMessage "-----------------------------------------------"

:: --- Ajustar chaves relacionadas à operação portátil ---
call :LogMessage "Definindo PortableOperation e PortableOperatingSystem como 0 no registro..."

:: PortableOperation
reg add "HKLM\SYSTEM\CurrentControlSet\Control" ^
    /v PortableOperation /t REG_DWORD /d 0 /f >> "%LOGFILE%" 2>&1

if %errorlevel%==0 (
    call :LogMessage "[OK] Chave PortableOperation definida para 0."
) else (
    call :LogMessage "[ERRO] Falha ao definir a chave PortableOperation."
)

:: PortableOperatingSystem
reg add "HKLM\SYSTEM\CurrentControlSet\Control" ^
    /v PortableOperatingSystem /t REG_DWORD /d 0 /f >> "%LOGFILE%" 2>&1

if %errorlevel%==0 (
    call :LogMessage "[OK] Chave PortableOperatingSystem definida para 0."
) else (
    call :LogMessage "[ERRO] Falha ao definir a chave PortableOperatingSystem."
)

call :LogMessage "Configurações de sistema portátil aplicadas."

:: ===============================================
:: ETAPA 2 - DISM
:: ===============================================
call :LogMessage "[2/3] Executando DISM /Online /Cleanup-Image /RestoreHealth ..."
call :LogMessage "[INFO] Iniciando verificação de integridade do sistema..."

dism /Online /Cleanup-Image /RestoreHealth >> "%LOGFILE%" 2>&1
set "DISM_ERR=%ERRORLEVEL%"

if %DISM_ERR% neq 0 (
    call :LogMessage "[ERRO] Falha ao executar DISM (código %DISM_ERR%)."
) else (
    call :LogMessage "[OK] DISM concluído com sucesso."
)

call :LogMessage "-----------------------------------------------"

:: ==========================
:: SEGUIR PARA SCRIPT DE UPGRADE
:: ==========================
call :LogMessage "Prosseguindo para rotina de upgrade..."
goto MAIN


:: ==========================================================
:: FUNÇÃO: REMOVER PASTA ROBUSTAMENTE (LOG RESUMIDO PARA WINDOWS.~BT)
:: ==========================================================
:RemoverPasta
set "ALVO=%~1"

if not exist "%ALVO%" (
    call :LogMessage "[i] Pasta não encontrada: %ALVO%"
    goto :EOF
)

:: Caso seja a pasta $WINDOWS.~BT, usar log resumido
if /I "%ALVO%"=="C:\$WINDOWS.~BT" (
    call :LogMessage "[*] Removendo pasta %ALVO% (modo rápido e log reduzido)..."
    attrib -R -A -S -H "%ALVO%" /S /D >nul 2>&1
    takeown /F "%ALVO%" /R /D Y >nul 2>&1
    icacls "%ALVO%" /T /Q /C /RESET >nul 2>&1
    rmdir /S /Q "%ALVO%" >nul 2>&1
    if exist "%ALVO%" (
        call :LogMessage "[x] Falha ao remover: %ALVO%"
    ) else (
        call :LogMessage "[OK] Pasta removida: %ALVO%"
    )
    goto :EOF
)

:: Caso contrário, manter log detalhado
call :LogMessage "[*] Processando pasta: %ALVO%"
echo [*] Removendo atributos (R,A,S,H)... >> "%LOGFILE%"
attrib -R -A -S -H "%ALVO%" /S /D >> "%LOGFILE%" 2>&1

echo [*] Tomando posse... >> "%LOGFILE%"
takeown /F "%ALVO%" /R /D Y >> "%LOGFILE%" 2>&1

echo [*] Resetando permissões NTFS... >> "%LOGFILE%"
icacls "%ALVO%" /T /Q /C /RESET >> "%LOGFILE%" 2>&1

echo [*] Tentando excluir... >> "%LOGFILE%"
rmdir /S /Q "%ALVO%" >> "%LOGFILE%" 2>&1

if exist "%ALVO%" (
    call :LogMessage "[x] Falha ao remover: %ALVO%"
) else (
    call :LogMessage "[OK] Pasta removida: %ALVO%"
)
goto :EOF

:: ==========================================================
:: FUNÇÃO DE LOG (unificada)
:: ==========================================================
:LogMessage
setlocal
for /f "tokens=1-3 delims=/" %%a in ("%date%") do set "YYYY=%%c" & set "MM=%%b" & set "DD=%%a"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "HH=%%a" & set "MN=%%b" & set "SS=%%c"
set "TIMESTAMP=%YYYY%-%MM%-%DD% %HH%:%MN%:%SS%"
>> "%LOGFILE%" echo %TIMESTAMP% - %*
echo %TIMESTAMP% - %*
endlocal
goto :eof


:: ==========================================================
:: BLOCO PRINCIPAL DO SCRIPT DE UPGRADE (mantido)
:: ==========================================================
:MAIN
call :LogMessage "=== Iniciando verificação e download da ISO ==="

:: (mantém toda sua lógica original de hash, download e montagem)
:: Download robusto + hash + montagem ISO
set /a RETRIES=0
if exist "%LOCALISO%" (
    call :LogMessage "ISO encontrada, verificando hash..."
    goto :CheckHash
) else (
    call :LogMessage "ISO não encontrada, iniciando download..."
    goto :DownloadLoop
)

:DownloadLoop
set /a RETRIES+=1
call :LogMessage "Iniciando download (tentativa %RETRIES%/%MAX_RETRIES%)"
if exist "%TMPDOWNLOAD%" del /f /q "%TMPDOWNLOAD%" >nul 2>&1

:: ===== DOWNLOAD ROBUSTO: TENTA BITS, SE FALHAR USA IWR =====
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Try {Import-Module BitsTransfer -ErrorAction Stop; Write-Host 'Iniciando BITS...' -ForegroundColor Cyan; Start-BitsTransfer -Source '%ONEDRIVE_URL%' -Destination '%TMPDOWNLOAD%' -DisplayName AtualizacaoW11 -RetryInterval 120 -RetryTimeout 14400 -TransferPolicy Always -Priority Foreground -ErrorAction Stop; Write-Output 'DOWNLOAD_OK'} Catch {Write-Host 'BITS falhou, tentando fallback HTTP...' -ForegroundColor Yellow; Try {$wc = New-Object System.Net.WebClient; $wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy(); $wc.DownloadFile('%ONEDRIVE_URL%', '%TMPDOWNLOAD%'); Write-Output 'DOWNLOAD_OK'} Catch {Write-Host 'ERRO DURANTE DOWNLOAD:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Yellow; Add-Content -Path '%LOGFILE%' -Value ('ERRO DOWNLOAD: ' + $_.Exception.Message); Write-Output 'DOWNLOAD_FAIL'}}"

:: ===== VERIFICA RESULTADO DO DOWNLOAD =====
set "DL_RESULT="
for /f "delims=" %%R in ('powershell -NoProfile -Command "Get-Content -Path '%LOGFILE%' | Select-String -SimpleMatch 'DOWNLOAD_' | Select-Object -Last 1 | ForEach-Object { $_.Line }"') do set "DL_RESULT=%%R"

if "%DL_RESULT%"=="DOWNLOAD_FAIL" (
    call :LogMessage "Falha no download detectada. Verifique conectividade e URL."
    pause
    goto :FinalCleanup
)

:: ===== VERIFICA HASH =====
for /f "tokens=*" %%H in ('powershell -NoProfile -Command "Get-FileHash -Path '%TMPDOWNLOAD%' -Algorithm SHA256 | Select-Object -ExpandProperty Hash"') do set "TMP_HASH=%%H"
if /I not "%TMP_HASH%"=="%EXPECTED_HASH%" (
    call :LogMessage "Hash do download inválida. Movendo para quarentena."
    move /Y "%TMPDOWNLOAD%" "%BAD_ISO_DIR%\%ISOFILENAME%.badhash_%RANDOM%" >nul 2>&1
    if %RETRIES% LSS %MAX_RETRIES% (
        timeout /t 10 >nul
        goto :DownloadLoop
    ) else (
        call :LogMessage "Falha: hash inválida após várias tentativas. Abortando."
        pause
        goto :FinalCleanup
    )
)

move /Y "%TMPDOWNLOAD%" "%LOCALISO%" >nul 2>&1
call :LogMessage "Download concluído e ISO movida."


:CheckHash
for /f "tokens=*" %%H in ('powershell -NoProfile -Command "Get-FileHash -Path '%LOCALISO%' -Algorithm SHA256 | Select-Object -ExpandProperty Hash"') do set "CURRENT_HASH=%%H"
if /I "%CURRENT_HASH%"=="%EXPECTED_HASH%" (
    call :LogMessage "ISO validada com sucesso."
    goto :MountISO
) else (
    call :LogMessage "Hash incorreta. Refazendo download."
    del "%LOCALISO%" >nul 2>&1
    goto :DownloadLoop
)

:MountISO
call :LogMessage "Montando ISO..."
set "DriveLetter="
for /f "delims=" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Try { $m = Mount-DiskImage -ImagePath '%LOCALISO%' -PassThru -ErrorAction Stop; Start-Sleep -Milliseconds 500; $vol = $m | Get-Volume -ErrorAction Stop; $vol.DriveLetter } Catch { Write-Output 'ERRO' }"') do (
    set "DriveLetter=%%i"
)
if "%DriveLetter%"=="ERRO" (
    call :LogMessage "ERRO ao montar ISO."
    goto :FinalCleanup
)
if not defined DriveLetter (
    call :LogMessage "Não foi possível determinar letra da ISO."
    goto :FinalCleanup
)
call :LogMessage "ISO montada em %DriveLetter%:"

set "SETUPPATH=%DriveLetter%:\sources\setupprep.exe"
set "ARGUMENTS=/auto upgrade /dynamicupdate disable /noreboot /quiet /compat ignorewarning /eula accept /product server /migratedrivers all /showoobe none /telemetry disable /reflectdrivers /copylogs C:\TempUpgradeLogs"

echo %date% %time% > "%REBOOT_FLAG%"
call :LogMessage "Executando setup (%SETUPPATH%)..."
START /WAIT "" "%SETUPPATH%" %ARGUMENTS%
set "SETUP_RET=%ERRORLEVEL%"
if %SETUP_RET% NEQ 0 (
    call :LogMessage "Setup retornou código %SETUP_RET%"
    if exist "%REBOOT_FLAG%" del /f /q "%REBOOT_FLAG%" >nul 2>&1
    goto :FinalCleanup
) else (
    call :LogMessage "Setup finalizado com sucesso. Reinício pendente."
    echo %date% %time% > "%COMPLETED_FLAG%"
)

:FinalCleanup
call :LogMessage "Limpando e finalizando..."
if exist "%LOCKFILE%" del /f /q "%LOCKFILE%" >nul 2>&1
if exist "%TEMPUPG%" rd /s /q "%TEMPUPG%" >nul 2>&1
call :LogMessage "Lockfile removido e limpeza concluída."
exit /b 0