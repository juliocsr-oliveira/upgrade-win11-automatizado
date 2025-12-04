Script de atualização automatica para o Windows.

Descrição Geral

Este projeto contém um script batch completamente automatizado, desenvolvido para realizar upgrades para o Windows 11 24H2 de forma segura, robusta e altamente tolerante a falhas.

Ele foi utilizado em ambiente de produção e inclui:

Criação de lockfiles

Logs locais e em rede

Download resiliente via BITS com fallback para WebClient

Verificação de integridade por SHA-256

Limpeza de pastas residuais do Windows Update

Ajustes de registro para desabilitar Portable OS

Execução de DISM

Montagem automática da ISO

Execução silenciosa do Setup

Flags de controle para reboot e conclusão

Proteção contra reinicializações incorretas

Fluxo Completo do Script

1. Criação de lockfile e criação da pasta de logs.

Garante que apenas uma instância do upgrade esteja rodando.

Lock é criado em C:\TempUpgrade\UpgradeTemp\UpgradeInProgress.lock.

2. Teste de rede + definição do local de logs

Faz até 5 tentativas de ping.

Caso consiga acessar o compartilhamento:

Logs são enviados para:
\\10.120.5.36\LogsUpgradeW11\<COMPUTERNAME>

Caso falhe:

Logs permanecem localmente em C:\TempUpgrade\<COMPUTERNAME>\.

3. Cópia dos logs de setup

Copia automaticamente:

setupact.log  
setuperr.log


Para a pasta de logs definida na etapa anterior.

4. Verificação de chave de reboot

Caso o sistema já tenha migrado e esteja apenas aguardando reinício:

Script aborta imediatamente

Evita corrupção de arquivos críticos da migração

Chave monitorada:

HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired

5. Reset de PortableOperation e PortableOperatingSystem

Ambas são definidas como 0:

HKLM\SYSTEM\CurrentControlSet\Control\PortableOperation
HKLM\SYSTEM\CurrentControlSet\Control\PortableOperatingSystem


Evita bloqueios de upgrade em sistemas marcados como portáteis.

6. Execução do DISM

Realiza:

dism /online /cleanup-image /restorehealth


Corrige componentes do Windows e evita erros estruturais na hora do setup.

7. Remoção de pastas residuais

Remove pastas que causam falhas no upgrade:

C:\$WINDOWS.~BT

C:\TempUpgradeW11\InvalidISOs

C:\Windows10Upgrade

C:\$WINDOWS.~WS

Processo robusto usando:

attrib

takeown

icacls

rmdir

8. Download da ISO (robusto)

Fluxo:

Tenta BITS (Start-BitsTransfer)

Se falhar → fallback para WebClient.DownloadFile

A ISO é salva primeiro como:

Win11.iso.download


Somente se o hash bater ela é renomeada para o nome final.

9. Verificação da ISO

Usa:

Get-FileHash -Algorithm SHA256


Se o hash for inválido:

ISO é movida para InvalidISOs/

O script baixa novamente (até 3 tentativas)

10. Montagem da ISO

Usa PowerShell:

Mount-DiskImage -PassThru
Get-Volume | Select DriveLetter


A letra da unidade é identificada dinamicamente.

11. Execução silenciosa do Setup

O script usa:

setupprep.exe /auto upgrade /dynamicupdate disable /noreboot /quiet /compat ignorewarning /eula accept /product server /migratedrivers all /showoobe none /telemetry disable /reflectdrivers /copylogs C:\TempUpgradeLogs


A opção /product server é obrigatória para contornar restrições de hardware.

12. Criação de flags

UpgradePendingReboot.flag

UpgradeCompleted.flag

Usadas para rastrear progresso e impedir loops.

13. Limpeza final

Remove:

pasta temporária

lockfile

E grava no log a finalização do processo.
Estrutura de Pastas Utilizada
C:\
 ├─ TempUpgrade\
 │   └─ <COMPUTERNAME>\
 │       ├─ UpgradeLog.log
 │       └─ (outros logs)
 │
 ├─ TempUpgradeW11\
 │   ├─ InvalidISOs\
 │   └─ Win11_24H2_BrazilianPortuguese_x64.iso
 │
 ├─ TempUpgradeLogs\
 │   ├─ setupact.log
 │   └─ setuperr.log


Atenção: embora os nomes sejam arbitrários, foram usados em produção, então mantê-los no README é recomendado.


14. Parâmetros configuráveis no topo do script

Variável	Descrição
WORKDIR	Pasta de trabalho
ISOFILENAME	Nome da ISO
ONEDRIVE_URL	URL de download
EXPECTED_HASH	Hash SHA256
LOCKFILE	Lock de execução
REBOOT_FLAG	Flag de reboot
COMPLETED_FLAG	Flag de conclusão


15. Requisitos

Windows 10 ou Windows 11 compatível

PowerShell habilitado

Permissões de administrador

Conectividade com o compartilhamento de logs (opcional)

Espaço em disco suficiente para a ISO (≥ 6 GB)

Espaço em disco suficiente para a atualização de fato (≥ 35 GB)

16. Erros Comuns e Diagnósticos

DOWNLOAD_FAIL

Falha de BITS + fallback

Problema de rede ou URL

Arquivo movido para InvalidISOs

Hash inválida

Arquivo corrompido durante download

Variações de rede

Refaça o download (o script faz automaticamente)

Falha ao montar ISO

Serviço de Virtual Disk desativado

ISO corrompida

Falta de permissões

Setup retornou código X

Códigos comuns:

Código	Significado
0	        Sucesso
0xC1900101	Driver bloqueando
0x8007001F	Política/driver problemático
0xC1900208	App incompatível
0xC1900204	Falha estruturada de compatibilidade

17. Segurança e Boas Práticas

O uso de lockfile impede execuções simultâneas.

Flags evitam corrupção pós-upgrade.

Logs consolidados permitem auditoria completa.

A pasta de ISOs inválidas permite rastrear falhas.
