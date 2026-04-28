# 🔐 DevSecOps Pipeline — Автоматический анализ уязвимостей

Полный пример DevSecOps-пайплайна с автоматическим сканированием Docker-образов и исходного кода.

## 🏗️ Архитектура пайплайна

```
┌─────────────────────────────────────────────────────────────────┐
│                     DevSecOps Pipeline                          │
├──────────┬──────────┬──────────┬──────────┬────────────────────┤
│  Stage 1 │  Stage 2 │  Stage 3 │  Stage 4 │     Stage 5        │
│   TEST   │   LINT   │  BUILD   │   SCAN   │  QUALITY GATE ⛔   │
├──────────┼──────────┼──────────┼──────────┼────────────────────┤
│ pytest   │Hadolint  │  Docker  │  Trivy   │ Block if CRITICAL  │
│SonarQube │          │  build   │  scan    │ CVEs found         │
│Gitleaks  │          │          │          │                    │
└──────────┴──────────┴──────────┴──────────┴────────────────────┘
                                                        │
                                               ✅ PASS  │  ❌ FAIL
                                                        ▼
                                             ┌──────────────────┐
                                             │  Stage 6: DEPLOY │
                                             │  (only on main)  │
                                             └──────────────────┘
```

## 🛠️ Стек технологий

| Инструмент | Назначение |
|---|---|
| **GitHub Actions / GitLab CI** | Оркестрация пайплайна |
| **Trivy** | Сканирование Docker-образов на CVE |
| **SonarQube** | SAST: анализ кода, покрытие тестами |
| **Hadolint** | Линтинг Dockerfile |
| **Gitleaks** | Поиск захардкоженных секретов |
| **pytest + coverage** | Юнит-тесты с покрытием |

## 📁 Структура проекта

```
devsecops-project/
├── .github/
│   └── workflows/
│       └── devsecops-pipeline.yml   # GitHub Actions pipeline
├── .gitlab-ci.yml                   # GitLab CI pipeline
├── app/
│   ├── app.py                       # Flask приложение
│   └── requirements.txt
├── docker/
│   └── Dockerfile.vulnerable        # ⚠️ Уязвимый образ для демо
├── tests/
│   └── test_app.py                  # Юнит-тесты
├── scripts/
│   └── run-local-pipeline.sh        # Запуск пайплайна локально
├── Dockerfile                       # Production Dockerfile (безопасный)
├── docker-compose.yml               # Локальная среда разработки
├── sonar-project.properties         # Конфигурация SonarQube
├── trivy.yaml                       # Конфигурация Trivy
├── trivy-secret.yaml                # Правила поиска секретов (Trivy)
├── .hadolint.yaml                   # Конфигурация Hadolint
└── .env.example                     # Шаблон переменных окружения
```

## 🚀 Быстрый старт

### 1. Локальный запуск демо-пайплайна

```bash
# Клонировать репозиторий
git clone <your-repo-url>
cd devsecops-project

# Запустить полный пайплайн локально
chmod +x scripts/run-local-pipeline.sh
./scripts/run-local-pipeline.sh
```

### 2. Запуск SonarQube локально

```bash
# Поднять SonarQube через Docker Compose
docker-compose up -d sonarqube sonarqube-db

# Дождаться запуска (около 2 минут)
# Открыть в браузере: http://localhost:9000
# Логин: admin / admin (изменить при первом входе)

# Создать проект и получить токен в UI, затем:
export SONAR_TOKEN=your_token_here
export SONAR_HOST_URL=http://localhost:9000

# Запустить сканирование
docker run --rm \
  --network devsecops-network \
  -v $(pwd):/usr/src \
  sonarsource/sonar-scanner-cli \
  -Dsonar.projectKey=devsecops-demo \
  -Dsonar.sources=app \
  -Dsonar.host.url=$SONAR_HOST_URL \
  -Dsonar.login=$SONAR_TOKEN
```

### 3. Ручной запуск Trivy

```bash
# Сборка образа
docker build -t devsecops-demo:local .

# Полное сканирование (отчёт)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity CRITICAL,HIGH,MEDIUM \
  devsecops-demo:local

# Quality Gate (блокировка на CRITICAL)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity CRITICAL \
  --exit-code 1 \
  devsecops-demo:local

# Сканирование уязвимого образа для сравнения
docker build -t devsecops-demo:vulnerable -f docker/Dockerfile.vulnerable .
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity CRITICAL,HIGH \
  devsecops-demo:vulnerable
```

### 4. Ручной запуск Hadolint

```bash
# Линтинг production Dockerfile
docker run --rm -i hadolint/hadolint < Dockerfile

# Линтинг уязвимого Dockerfile (увидите много предупреждений)
docker run --rm -i hadolint/hadolint < docker/Dockerfile.vulnerable
```

### 5. Запуск юнит-тестов

```bash
pip install -r app/requirements.txt pytest pytest-cov
pytest tests/ --cov=app --cov-report=term-missing -v
```

## ⛔ Как работает Quality Gate

Quality Gate — это **жёсткий блокировщик** деплоя. Пайплайн автоматически останавливается если:

1. **Trivy** находит хотя бы одну `CRITICAL` уязвимость в Docker-образе → `exit-code 1`
2. **SonarQube** не проходит Quality Gate (покрытие < 70%, BLOCKER-issues)
3. **Gitleaks** находит захардкоженные пароли/токены в коде
4. **Hadolint** находит ошибки (`error` level) в Dockerfile

```
# Пример блокировки Trivy:
CRITICAL: 2 vulnerabilities found
trivy image --severity CRITICAL --exit-code 1 myimage:latest
→ exit code: 1  ← Pipeline FAILS here, deploy is BLOCKED
```

## 📊 Демонстрация уязвимостей

Проект содержит `docker/Dockerfile.vulnerable` с намеренными проблемами:
- Устаревший базовый образ `python:3.8` (множество CVE)
- Запуск от root (нет `USER`)
- Захардкоженные пароли в `ENV`
- Открытый SSH-порт 22
- Плохие практики Dockerfile

Это позволяет сравнить результаты Trivy и Hadolint для **безопасного** и **уязвимого** образов.

## 🔧 Настройка для реального проекта

### GitHub Actions

1. В Settings → Secrets добавьте:
   - `SONAR_TOKEN` — токен SonarQube
   - `SONAR_HOST_URL` — URL SonarQube (напр. `https://sonarcloud.io`)

2. Push в `main` ветку запустит пайплайн.

### GitLab CI

1. В Settings → CI/CD → Variables добавьте:
   - `SONAR_TOKEN`
   - `SONAR_HOST_URL`

2. `CI_REGISTRY_*` переменные GitLab заполняет автоматически.

## 📚 Полезные ссылки

- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [SonarQube Docs](https://docs.sonarqube.org/)
- [Hadolint Rules](https://github.com/hadolint/hadolint/wiki/DL3002)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [OWASP Top 10 CI/CD Security Risks](https://owasp.org/www-project-top-10-ci-cd-security-risks/)
