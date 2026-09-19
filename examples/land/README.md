# land: пример конфигурации доставки

Публичный пример Docker-сборки, Woodpecker pipeline и Kubernetes-манифестов
для статического сайта Hugo + Caddy. Файлы воспроизводят конфигурацию,
проверенную в homelab 19 сентября 2026 года;

[Инженерное описание](../../docs/land-delivery.md) объясняет архитектуру,
зависимости, выпуск версии и откат. [Журнал работ](../../docs/ops/land-gitops-delivery.md)
содержит реальные ошибки и результаты проверок.

## Состав

| Файл | Назначение |
|---|---|
| [Dockerfile](Dockerfile) | Сборка Hugo и копирование результата в корень Caddy |
| [.dockerignore](.dockerignore) | Исключение Git и локальных результатов сборки из контекста |
| [.woodpecker.yml](.woodpecker.yml) | Проверка HTML, сборка и push образа с тегом SHA |
| [deploy/deployment.yaml](deploy/deployment.yaml) | Одна реплика на amd64, readiness probe, ресурсы и pull secret |
| [deploy/service.yaml](deploy/service.yaml) | Внутренний HTTP Service |

## Что нужно для использования

В рабочем приватном репозитории эти файлы лежат в корне `land`, рядом с `site/`.
Каталог `site/` с исходниками, темой и статическими файлами сюда не включён.
Без него Dockerfile и pipeline не соберут сайт. Сгенерированный `site/public/`
не требуется: HTML создаётся при сборке.

```text
land/
├── .dockerignore
├── .woodpecker.yml
├── Dockerfile
├── site/                   # приватные исходники Hugo
│   └── config.toml
└── deploy/
    ├── deployment.yaml
    └── service.yaml
```

Для повторения нужны свой Hugo-сайт, доступный Registry, Woodpecker с Docker
backend и настроенный k3s/ArgoCD. Адрес `registry.homelab.local:5000` и тег образа
относятся к этому стенду. Для другого окружения их нужно заменить в pipeline
и Deployment. В `site/config.toml` проверенного сайта используется `baseURL = "/"`.

Порядок подготовки секретов, DNS/TLS и подключения ArgoCD приведён
в [инженерном описании](../../docs/land-delivery.md).
Namespace, секреты и ArgoCD Application создаются отдельно; их нет в `deploy/`.

Вложенный `.woodpecker.yml` служит примером для приватного `land`.
CI публичного `homelab-infrastructure` задаётся другим файлом в корне репозитория.

## Проверенная версия

Deployment указывает на образ с тегом
`cee7e25dc06e319b248c8deee38554c4564fec19` — SHA исходников после исправления
заголовка сайта. Этот образ прошёл сборку, push и запуск на `k3-worker-2`.
Тег сохраняет связь с исходным коммитом; политика запрета перезаписи тегов
в Registry не настроена. Базовые образы также не закреплены по digest.
