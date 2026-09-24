# Lab: Windows Server 2025 golden image для Proxmox — Cloudbase-Init, Sysprep, ConfigDrive2 (2026-09-22…24)

Журнал учебного эксперимента (вне основной инфраструктуры): подготовка шаблона Windows Server в Proxmox VE и проверка,
что клон сам получает имя, сеть и пароль администратора из Proxmox — так же, как Linux-VM
получают их через cloud-init. Формат: цель → схема → исполнение → инциденты → итог → границы.

Все команды выполнялись удалённо с хоста Proxmox, без RDP и без изменения сети:
доступ внутрь Windows шёл через QEMU Guest Agent (`qm guest exec`).

---

## Контекст и цель

Linux-VM в этом homelab создаются клонированием Ubuntu-шаблона с cloud-init
(Terraform + `bpg/proxmox`, см. [terraform/](../../terraform/)). Для Windows готового
cloud-образа нет — его нужно собрать самому.

**Цель:** проверить, как тот же подход (template → clone → guest customization) работает
с Windows: собрать шаблон и доказать пробным клоном, что он получает свои hostname,
DHCP-адрес и пароль администратора без ручной настройки внутри гостя.

**Стенд:** Proxmox VE 9.1.6, Windows Server 2025 Standard (Desktop Experience, русская
локализация), VirtIO drivers 0.1.302, Cloudbase-Init 1.1.8. Шаблон: 2 vCPU, 4 GiB RAM,
64 GiB thin disk на LVM-thin, `q35` + OVMF, VirtIO SCSI single + VirtIO NIC.

## Как это устроено

```
Proxmox (имя VM, cipassword, ipconfig0)
   │  генерирует ISO ConfigDrive2 (OpenStack-формат) на cloud-init диске
   ▼
openstack/latest/meta_data.json   ← uuid, admin_pass
openstack/latest/user_data        ← #cloud-config: hostname
openstack/content/0000            ← сеть (DHCP)
   │
   ▼
Cloudbase-Init в клоне (ConfigDriveService)
   ├─ specialize (Sysprep, cloudbase-init-unattend.conf)
   └─ служба после загрузки (cloudbase-init.conf) → пароль, hostname, сеть
```

| Роль | Linux-шаблон | Windows-шаблон |
|---|---|---|
| Агент первичной настройки в госте | cloud-init | Cloudbase-Init |
| Обезличивание образа | готовый cloud image | Sysprep `/generalize` |
| Что передаётся | hostname, SSH-ключ | hostname, пароль администратора |
| Канал передачи | cloud-init диск Proxmox | cloud-init диск Proxmox (`citype=configdrive2`) |

## Исполнение

### 1. Базовая VM и драйверы

VM создана через `qm` выключенной, установка с двух ISO: Windows и VirtIO. Системный диск
стал виден установщику после загрузки драйвера `vioscsi`. После установки — VirtIO guest
tools и QEMU Guest Agent; проверка со стороны Proxmox:

```bash
qm agent 9200 ping; echo $?          # 0 — агент отвечает (успешный ping ничего не печатает)
qm agent 9200 get-osinfo             # Windows Server 2025, build 26100
```

Из шаблона убраны зависимости от ISO: загрузка только с системного диска, приводы пустые.

```bash
qm set 9200 --boot order=scsi0 --sata0 none,media=cdrom --sata1 none,media=cdrom
```

### 2. Настройка Cloudbase-Init

Установщик по умолчанию перебирает все известные источники метаданных (CloudStack, EC2,
MaaS, OpenNebula…). На первой загрузке без ConfigDrive это видно в логе: CloudStack
пошёл по HTTP на шлюз домашней сети (DHCP-сервер), получил отказ, и поиск занял
около 6,5 минут до `No metadata service found`.

В обоих конфигах источник ограничен тем, что реально даёт Proxmox:

```ini
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
```

`cloudbase-init.conf` (служба после загрузки) — дополнительно:

```ini
check_latest_version=false     ; шаблон не ходит в интернет проверять версию
first_logon_behaviour=no       ; не требовать смену пароля при первом входе
rename_admin_user=false        ; встроенный администратор не переименовывается
allow_reboot=true              ; смена hostname требует перезагрузки
```

`cloudbase-init-unattend.conf` (этап specialize внутри Sysprep) — только `metadata_services`.
`allow_reboot=false` там оставлен намеренно: на этом этапе перезагрузку делает сама
установка Windows.

**Кодировка.** На русской Windows установщик записал `username=Администратор` в ANSI (CP1251)
без BOM — проверено побайтно (`Format-Hex`: «А» = `C0`). Правка выполнялась с сохранением
кодировки и идемпотентно (сначала удалить ключи, затем добавить), с резервными копиями `.orig`
и проверкой через `Compare-Object`. Пример приёма через guest agent:

```bash
qm guest exec 9200 -- powershell -NoProfile -Command "\$p='C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf'; \$c=Get-Content \$p -Encoding Default | Where-Object { \$_ -notmatch '^(metadata_services|allow_reboot)=' }; \$c+='metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService','allow_reboot=true'; Set-Content \$p \$c -Encoding Default"
```

### 3. Подготовка к Sysprep

Перед запечатыванием проверены метки ожидающей перезагрузки и фактическая сборка:

```powershell
Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object CurrentBuild,UBR
```

Результат показал, что «обновления установлены» было верно только наполовину:
`UBR = 1` (чистый RTM), хотя накопительное обновление уже скачалось и встало в очередь.
По журналу `WindowsUpdateClient` (события 43 — начало установки, 19 — успех, 20 — ошибка)
оно завершилось только на следующей перезагрузке, после чего обновление .NET потребовало ещё
одну. После двух перезагрузок все метки `False`, сборка **26100.33438**.
Перед Sysprep — snapshot и очистка логов Cloudbase-Init.

### 4. Sysprep

```bash
qm guest exec 9200 -- powershell -NoProfile -Command "Start-Process -FilePath 'C:\Windows\System32\Sysprep\Sysprep.exe' -ArgumentList '/generalize /oobe /shutdown /unattend:C:\Windows\Temp\cbi-unattend.xml'"
watch -n 30 qm status 9200     # ждать status: stopped
```

`Unattend.xml` поставляется с Cloudbase-Init: на этапе specialize он вызывает Cloudbase-Init
с `cloudbase-init-unattend.conf`. Прогресс отслеживался по
`C:\Windows\System32\Sysprep\Panther\setupact.log`.

### 5. Cloud-init диск и пробный клон

На выключенном шаблоне:

```bash
qm set 9200 --ide2 local-lvm:cloudinit --citype configdrive2 --ipconfig0 ip=dhcp
```

Пробный клон с тестовым паролем, который не попадает в историю shell:

```bash
qm clone 9200 200 --name win-lab-01 --full
read -rs PW; qm set 200 --cipassword "$PW"; unset PW
```

Содержимое диска проверено до запуска — не только через `qm cloudinit dump`,
но и по реальному ISO (см. инцидент 3):

```bash
qm cloudinit update 200
mount -o ro /dev/pve/vm-200-cloudinit /mnt/ci200
grep -c admin_pass /mnt/ci200/openstack/latest/meta_data.json    # 1
umount /mnt/ci200
```

## Инциденты и решения

### 1. Sysprep: кавычки потерялись на пяти слоях

Первый запуск с `/unattend:"C:\Program Files\...\Unattend.xml"` упал сразу:

```
SYSPRP ParseCommands:Found supported command line option 'UNATTEND'
SYSPRP ParseCommands:Malformed command line detected; no dash or slash present in option
SYSPRP WinMain: Unable to parse command-line arguments to sysprep
```

Команда проходила bash → `qm` → guest agent → командную строку Windows → PowerShell → Sysprep;
кавычки вокруг пути с пробелами были съедены на одном из слоёв, и Sysprep получил путь,
разрезанный по пробелу. Состояние системы не изменилось — ошибка на этапе разбора аргументов.

**Решение:** не подбирать экранирование, а убрать пробелы — `Unattend.xml` скопирован
в `C:\Windows\Temp\cbi-unattend.xml`.

### 2. Второй запуск «ничего не делал»

Новый запуск не оставил ни строки в логе. `Get-Process sysprep` показал два процесса:
первый, упавший, висел на окне с ошибкой. Guest agent — служба, поэтому окно было
в невидимом session 0 и на консоли VM не отображалось; второй экземпляр упирался в первый.

**Решение:** `Stop-Process -Name sysprep -Force`, повторный запуск; generalize прошёл,
VM выключилась сама.

**Побочный урок:** `exitcode: 1` у цепочки `Stop-Process …; Get-Process … -ErrorAction SilentlyContinue`
дал последний `Get-Process`, не нашедший процесс, — то есть ожидаемый результат. Код возврата
в цепочке — это код последней команды; судить нужно по `out-data`/`err-data`.

### 3. `qm cloudinit dump` показал не то, что записано на диск

`qm cloudinit dump 200 meta` вывел Linux-вариант метаданных без `admin_pass`.
По исходникам `qemu-server` для Windows `ostype` используется отдельная функция
генерации (`cloudbase_configdrive2_metadata`), которая кладёт пароль в `meta_data.json`
открытым текстом. Смонтированный read-only ISO клона подтвердил: `admin_pass` на месте.
Вывод — проверять сам артефакт, а не только отчёт инструмента о нём.

### 4. Hostname приходит не через метаданные

В логе клона: `SetHostNamePlugin — Hostname not found in metadata`. Proxmox кладёт имя
в `user_data` как `#cloud-config`. Его разобрал `UserDataPlugin`:
`Changing hostname to 'win-lab-01'`. Имя в Windows применяется после перезагрузки;
автоперезагрузка Cloudbase-Init совпала с перезагрузкой, которую уже выполняла Windows,
и не прошла (`Reboot failed`), поэтому имя стало активным после ещё одного `qm reboot`.

Ожидаемый «шум» в логе, не влияющий на результат: `Plugin 'manage_etc_hosts' / 'fqdn' /
'password' / 'chpasswd' / 'package_upgrade' is currently not supported` — это Linux-ключи
cloud-config, которые Proxmox генерирует для любых ОС.

## Итог

Пробный клон `win-lab-01` из запечатанного шаблона:

| Проверка | Результат |
|---|---|
| Источник метаданных | `Metadata service loaded: 'ConfigDriveService'` — сразу, без походов по сети |
| Hostname | `win-lab-01` (через cloud-config, после одной дополнительной перезагрузки) |
| Сеть | адрес из домашней подсети, `PrefixOrigin: Dhcp` |
| Пароль администратора | `SetUserPasswordPlugin: Using admin_pass metadata user password` |
| Вход | вход под встроенным администратором с паролем из Proxmox — успешно, без принудительной смены |

Кириллическое имя пользователя из ANSI-конфига Cloudbase-Init прочитал корректно:
пароль применён к существующей учётной записи.

После проверки клон удалён вместе с дисками (`qm destroy 200 --purge`), включая cloud-init
диск с тестовым паролем.

## Безопасность

- Для Windows Proxmox хранит `cipassword` **открытым текстом** — в конфиге VM и на
  cloud-init диске (для Linux он хешируется). Поэтому пароль был тестовым, а клон удалён.
- При переносе в Terraform тот же пароль окажется в state (`sensitive = true` скрывает его
  только в выводе). Нужны отдельный state с ограниченным доступом и ротация пароля после
  первого входа.
- Пароль задавался через `read -rs`, чтобы не попасть в `~/.bash_history`.

## Границы проверки

- Шаблон собран вручную; Packer и автоматическая сборка образа не использовались.
- VM не конвертирована в Proxmox template: `qm template` отказывает, пока у VM есть snapshot
  (`unable to create template, because VM contains snapshots`). Для учебной цели
  конвертация не потребовалась — клон проверен как full clone.
- Создание клона через Terraform не выполнялось: принцип тот же, что у Linux-VM этого
  репозитория (`clone.vm_id`, блок `initialization`), отличаются только передаваемые данные.
- Проверен один клон; независимость двух клонов и повторное создание не проверялись.
- Активация Windows и доменные сценарии (AD/GPO) вне рамок.

## Инструкция для повторения

Порядок проверен в этой операции. Команды Proxmox выполняются на хосте PVE под root;
команды Windows — через `qm guest exec <vmid> -- powershell -NoProfile -Command "…"`
(в bash `$` внутри двойных кавычек экранируется как `\$`) либо в консоли VM.
VMID, storage и bridge подставить свои.

### A. VM и установка Windows

1. Загрузить в storage `local` ISO Windows Server 2025 и VirtIO (`virtio-win-*.iso` со stable-канала),
   записать SHA-256 VirtIO ISO.
2. Создать выключенную VM. Команда восстановлена по итоговому `qm config` этой операции —
   сверить параметры с версией PVE перед запуском:

   ```bash
   qm create 9200 --name windows-server-2025-template --ostype win11 \
     --machine q35 --bios ovmf --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=0 \
     --cpu x86-64-v2-AES --sockets 1 --cores 2 --memory 4096 --balloon 0 \
     --scsihw virtio-scsi-single --scsi0 local-lvm:64,discard=on,iothread=1 \
     --net0 virtio,bridge=vmbr0 --agent enabled=1 \
     --sata0 local:iso/<windows-server-2025>.iso,media=cdrom \
     --sata1 local:iso/<virtio-win>.iso,media=cdrom \
     --boot 'order=sata0;scsi0'
   qm config 9200
   ```

   `ostype win11` — тип PVE для Windows 11/2022/2025; он же включает Windows-вариант
   ConfigDrive2. TPM и Secure Boot для этой лабораторной VM не добавлялись.
3. Установить Windows через консоль. Диск не виден — «Загрузить драйвер» → VirtIO ISO →
   `vioscsi\2k25\amd64`.
4. В Windows установить VirtIO guest tools с того же ISO (драйверы + QEMU Guest Agent).
   Проверка с хоста: `qm agent 9200 ping; echo $?` → `0`;
   в Windows `Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK'` — пусто.
5. Отвязать шаблон от ISO:
   `qm set 9200 --boot order=scsi0 --sata0 none,media=cdrom --sata1 none,media=cdrom`.

### B. Cloudbase-Init

6. Внутри VM скачать stable x64 MSI с официального сайта Cloudbase, проверить до запуска:
   `Get-AuthenticodeSignature <msi>` → `Status: Valid`; записать `Get-FileHash <msi> -Algorithm SHA256`
   и фактическую версию.
7. Узнать точное имя встроенного администратора (на локализованной Windows оно переведено):
   `Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' } | Select-Object Name, SID`.
8. Установить MSI: username — имя из п. 7, группа — локализованная группа администраторов,
   **Use metadata password** — да, служба под **LocalSystem**. На последнем экране
   **не** отмечать запуск Sysprep и выключение: сначала конфиги.
9. `qm snapshot 9200 pre-cbi-first-boot` — до первой загрузки со службой Cloudbase-Init.
10. Сделать резервные копии конфигов и ограничить источник метаданных в **обоих** файлах.
    Правка идемпотентна и сохраняет кодировку ANSI (`-Encoding Default`):

    ```bash
    qm guest exec 9200 -- powershell -NoProfile -Command "\$d='C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf'; foreach (\$f in 'cloudbase-init.conf','cloudbase-init-unattend.conf') { \$p=Join-Path \$d \$f; if (-not (Test-Path \"\$p.orig\")) { Copy-Item \$p \"\$p.orig\" }; \$c=Get-Content \$p -Encoding Default | Where-Object { \$_ -notmatch '^metadata_services=' }; \$c+='metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService'; Set-Content \$p \$c -Encoding Default }"
    ```

11. Только в `cloudbase-init.conf` — дополнительные ключи:

    ```bash
    qm guest exec 9200 -- powershell -NoProfile -Command "\$p='C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf'; \$c=Get-Content \$p -Encoding Default | Where-Object { \$_ -notmatch '^(check_latest_version|first_logon_behaviour|rename_admin_user|allow_reboot)=' }; \$c+='check_latest_version=false','first_logon_behaviour=no','rename_admin_user=false','allow_reboot=true'; Set-Content \$p \$c -Encoding Default"
    ```

12. Проверить результат: `Compare-Object` с `.orig` (ожидаемые строки ушли/пришли),
    `Select-String -Path '<conf>\*.conf' -Pattern '^metadata_services='` — в обоих файлах
    только ConfigDriveService; `Format-Hex` первых байтов — нет BOM (`EF BB BF`),
    кириллица осталась однобайтовой.

### C. Обновления и Sysprep

13. Цикл до чистого состояния: установить обновления → `qm reboot 9200` → проверить метки
    перезагрузки и `CurrentBuild`/`UBR` (команды — раздел «Подготовка к Sysprep»).
    Повторять, пока все метки `False`, а Windows Update не находит новых обновлений.
14. `qm snapshot 9200 pre-sysprep --description "<сборка>, <что внутри>, before sysprep"`.
15. Очистить логи Cloudbase-Init:
    `Remove-Item 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\*.log'`.
16. Скопировать файл ответов в путь без пробелов и запустить Sysprep:

    ```bash
    qm guest exec 9200 -- powershell -NoProfile -Command "Copy-Item 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml' 'C:\Windows\Temp\cbi-unattend.xml'; Start-Process -FilePath 'C:\Windows\System32\Sysprep\Sysprep.exe' -ArgumentList '/generalize /oobe /shutdown /unattend:C:\Windows\Temp\cbi-unattend.xml'"
    ```

17. Через минуту проверить, что Sysprep действительно работает, а не упал:
    `Get-Content 'C:\Windows\System32\Sysprep\Panther\setupact.log' -Tail 15` — идут строки
    `Sysprep_Generalize…` без `Error`. Если нового запуска в логе нет — `Get-Process sysprep`
    (инцидент 2). Ждать `qm status 9200` → `stopped`. **После этого исходную VM не запускать.**

### D. Cloud-init диск и проверка клоном

18. `qm set 9200 --ide2 local-lvm:cloudinit --citype configdrive2 --ipconfig0 ip=dhcp`.
19. Клон и тестовый пароль (Windows требует сложный пароль, имя — не длиннее 15 символов):

    ```bash
    qm clone 9200 200 --name win-lab-01 --full
    read -rs PW; qm set 200 --cipassword "$PW"; unset PW
    ```

20. Проверить реальный ISO до запуска: `qm cloudinit update 200`, `mount -o ro` тома
    `vm-200-cloudinit`, `grep -c admin_pass openstack/latest/meta_data.json` → `1`,
    `grep hostname openstack/latest/user_data`, `umount`.
21. `qm start 200`, подождать ~10 минут (specialize, перезагрузка, служба Cloudbase-Init).
    Проверить `hostname`, `Get-NetIPAddress -AddressFamily IPv4` (`PrefixOrigin: Dhcp`) и логи
    `cloudbase-init-unattend.log` / `cloudbase-init.log`: `Metadata service loaded: 'ConfigDriveService'`,
    `Setting hostname`, `Using admin_pass metadata user password`. Если имя ещё старое —
    `qm reboot 200` и проверить снова.
22. Войти под встроенным администратором с тестовым паролем. После проверки —
    `qm stop 200; qm destroy 200 --purge`.
23. Для linked clone: удалить snapshot шаблона (`qm delsnapshot`) и выполнить
    `qm template 9200`. В этой операции шаг не выполнялся.

## Чему научил эксперимент

- Шаблон проверяется клоном, а не загрузкой самого шаблона: первая загрузка после Sysprep
  должна достаться клону.
- Snapshot перед необратимыми шагами (первый запуск Cloudbase-Init, Sysprep) делает
  эксперименты дешёвыми.
- Аргументы с пробелами через несколько слоёв (ssh/agent/cmd/PowerShell) — убрать пробелы,
  а не бороться с экранированием.
- Процесс, запущенный службой, может висеть на невидимом окне — `Get-Process` первым делом.
- «Обновления установлены» проверяется по сборке (`UBR`) и меткам перезагрузки, а не по
  экрану Windows Update.
