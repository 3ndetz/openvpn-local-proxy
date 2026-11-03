# OpenVPN Local Proxy

Локальный HTTP- и SOCKS5-прокси для Windows через отдельное подключение OpenVPN в WSL 2. Оба протокола принимаются на одном TCP-порту. Подключение используют только приложения, в которых явно указан прокси; системный прокси Windows не включается.

## Требования

- Windows 10/11, WSL 2 с Ubuntu и включённым systemd; Docker не нужен.
- OpenVPN-профиль `.ovpn` и учётные данные. Файлы должны постоянно находиться на диске Windows.
- Доступ администратора Windows и интернет для установки пакетов в Ubuntu.
- В Ubuntu должны работать `apt` и `dpkg`. Если пакетный менеджер сообщает о незавершённой установке, сначала устраните эту проблему в Ubuntu.
- Порт 2079 должен быть свободен. В WSL используются сетевое пространство `localovpn`, интерфейс `ovpnh` и подсеть `10.249.208.0/30`.

Для установки WSL см. официальную документацию Microsoft: https://learn.microsoft.com/windows/wsl/install. Проверьте доступные дистрибутивы командой `wsl --list --verbose` и убедитесь, что в Ubuntu работает `systemctl`.

## Учётные данные

Создайте файл, например `C:\VPN\credentials.env`, вне репозитория:

```dotenv
login=your_login
password=your_password
private_key=private_key_password_if_required
```

`login` и `password` обязательны; `private_key` — пароль закрытого ключа, если он зашифрован. Пустое значение допустимо. Не добавляйте реальные данные или `.ovpn` в Git. Файл должен быть доступен выбранной Ubuntu через `/mnt/c`. Для паролей с переводами строк формат не подходит.

## Установка

Откройте PowerShell **от имени администратора** в папке проекта:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 `
  -Profile 'C:\VPN\client.ovpn' `
  -Credentials 'C:\VPN\credentials.env' `
  -Distro 'Ubuntu-24.04' -Port 2079
```

Укажите фактическое имя дистрибутива и свои пути. Установка ставит пакеты, создаёт службу `openvpn-local-proxy` в Ubuntu и задачу Windows `OpenVPN Local Proxy`, которая запускается при входе пользователя. Служба автоматически перезапускается после аварийного завершения. OpenVPN самостоятельно переподключается при кратковременном обрыве. При повторном входе задача запускает WSL и обновляет привязку Windows к IP WSL. При выключенном компьютере или до входа пользователя прокси недоступен.

Проверка в Windows:

```powershell
curl.exe -sS -o NUL -w "HTTP %{http_code}`n" --max-time 20 --proxy http://127.0.0.1:2079 https://example.com/
curl.exe -sS -o NUL -w "HTTP %{http_code}`n" --max-time 20 --proxy socks5h://127.0.0.1:2079 https://example.com/
```

Для внутреннего ресурса замените URL на его адрес. `socks5h` означает разрешение имени через прокси. Доступ к ресурсам зависит от прав и маршрутов VPN-сервера.

## Chrome и SwitchyOmega

В расширении SwitchyOmega создайте **Proxy Profile**. Выберите протокол **HTTP**, сервер `127.0.0.1`, порт `2079`, включите использование одного прокси для всех протоколов и нажмите **Apply changes**. Затем выберите созданный профиль в меню расширения. Чтобы вернуть прямое соединение, выберите **Direct**. Эти настройки относятся к браузеру.

## Диагностика

```powershell
wsl -d Ubuntu-24.04 -u root -- systemctl status openvpn-local-proxy --no-pager
wsl -d Ubuntu-24.04 -u root -- journalctl -u openvpn-local-proxy -n 80 --no-pager
wsl -d Ubuntu-24.04 -u root -- cat /run/openvpn-local-proxy/vpn.log
```

Проверьте адрес и порт в браузере, логин и пароль, доступность VPN-сервера и выбранный профиль SwitchyOmega. Не публикуйте журнал, не проверив его на адреса и другую конфиденциальную информацию. В туннеле установлен MTU 900: это помогает при потере крупных TLS-пакетов браузеров.

## Остановка и удаление

```powershell
wsl -d Ubuntu-24.04 -u root -- systemctl disable --now openvpn-local-proxy
Unregister-ScheduledTask -TaskName 'OpenVPN Local Proxy' -Confirm:$false
netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=2079
```

Для полного удаления также удалите `/opt/openvpn-local-proxy`, `/etc/openvpn-local-proxy` и `/etc/systemd/system/openvpn-local-proxy.service` в Ubuntu и папку `%LOCALAPPDATA%\OpenVPNLocalProxy` в Windows. Исходные профиль и файл учётных данных удаляются отдельно владельцем.
