# install-lamp-angie

Bash-скрипт для автоматической установки веб-стека на базе **Angie + PHP 8.4-FPM + MariaDB** с автоматическим SSL через встроенный ACME-клиент Angie.

## Стек

| Компонент | Версия       | Источник                      |
|-----------|--------------|-------------------------------|
| Angie     | latest       | angie.software (official)     |
| PHP-FPM   | 8.4          | ondrej/php (Ubuntu) / sury.org (Debian) |
| MariaDB   | distro       | apt                           |

## Поддерживаемые ОС

- Ubuntu 22.04 / 24.04
- Debian 12

## Требования

- Сервер с чистой ОС
- Root-доступ
- Публичный IP
- **DNS A-запись домена должна указывать на сервер** до запуска скрипта — это обязательное условие для выпуска SSL-сертификата

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nloveuser/lamp-angie/refs/heads/main/install.sh)
```

Или скачать и запустить вручную:

```bash
curl -fsSL https://raw.githubusercontent.com/nloveuser/lamp-angie/refs/heads/main/install.sh -o install.sh
bash install.sh
```

Скрипт интерактивно спросит:

```
  Domain name (e.g. example.com): example.com
  Email for Let's Encrypt:        admin@example.com
```

### Кастомный пароль MariaDB

По умолчанию пароль генерируется автоматически. Чтобы задать свой:

```bash
DB_ROOT_PASS="yourpassword" bash install-lamp-angie.sh
```

## Версионирование

Версия и changelog хранятся прямо в заголовке скрипта:

```bash
# version: 1.0.0
# change-log:
#   1.0.0 - Initial release
```

Скрипт при запуске автоматически парсит и выводит текущую версию. При обновлении скрипта достаточно поменять `version:` и добавить строку в `change-log:`.

## Что делает скрипт

1. Добавляет официальный репозиторий Angie и устанавливает веб-сервер
2. Добавляет репозиторий ondrej/php (Ubuntu) или sury.org (Debian), устанавливает PHP 8.4-FPM с модулями
3. Устанавливает MariaDB, применяет базовый хардениг (удаление анонимных пользователей, тестовой БД)
4. Настраивает Angie с проксированием запросов через Unix-сокет на PHP-FPM
5. Настраивает автоматический SSL через встроенный ACME-клиент Angie (Let's Encrypt)
6. Включает HTTP → HTTPS редирект и HTTP/2
7. Создаёт тестовую страницу `/info.php`
8. Включает все сервисы в автозагрузку

## SSL

Сертификат выпускается автоматически при первом обращении к домену. Используется **встроенный ACME-модуль Angie** — certbot не требуется. Продление происходит автоматически без каких-либо cron-задач.

ACME-аккаунт и сертификаты хранятся в `/etc/angie/acme/`.

## PHP-модули

Устанавливаются следующие модули:

`cli` `fpm` `mysql` `mbstring` `xml` `curl` `zip` `gd` `bcmath` `intl` `opcache`

## Структура файлов после установки

```
/etc/angie/
├── acme/                        # ACME аккаунт и сертификаты
├── http.d/
│   └── example.com.conf         # Конфиг вашего домена
└── snippets/
    └── fastcgi-php.conf         # FastCGI параметры для PHP

/var/www/html/                   # Веб-корень
```

## После установки

Проверить работу стека:

```
https://example.com/info.php
```

Удалить тестовую страницу после проверки:

```bash
rm /var/www/html/info.php
```

## Управление сервисами

```bash
systemctl status angie
systemctl status php8.4-fpm
systemctl status mariadb

systemctl reload angie          # применить изменения конфига без даунтайма
angie -t                        # проверить конфиг перед reload
```

## Веб-корень и права

Веб-корень по умолчанию: `/var/www/html`

Для работы PHP-скриптов с записью в директории:

```bash
chown -R www-data:www-data /var/www/html
```
