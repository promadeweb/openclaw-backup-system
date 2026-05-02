# OpenClaw Backup System

Sistema de respaldo diario para la carpeta de datos de OpenClaw.

Este repositorio incluye un instalador autocontenido para dejar configurado un backup diario en un servidor Linux con cron y logrotate. No necesitas clonar el repositorio en la máquina destino.

## Archivos incluidos

- `install.sh`: instalador autocontenido. Crea e instala el script de backup en el servidor.
- `backup-openclaw.sh`: versión fuente del script de backup. El instalador también incluye este contenido internamente.

## Qué hace el backup

El script instalado `backup-openclaw.sh` realiza las siguientes tareas:

1. Valida que exista el directorio fuente `/root/.openclaw`.
2. Crea un backup del día con el formato:

   ```text
   YYYY.MM.DD-OpenClaw
   ```

3. Mantiene el backup más reciente sin comprimir.
4. Comprime backups anteriores como `.zip`.
5. Mantiene como máximo 10 backups.
6. Elimina los backups más antiguos cuando se supera ese límite.
7. Escribe logs en:

   ```text
   /var/log/openclaw-backups/openclaw-backup.log
   ```

8. Usa un lock en `/tmp/openclaw-backup.lock` para evitar ejecuciones simultáneas.
9. Permite que el grupo administrador del sistema pueda listar carpetas y leer archivos/logs.

## Requisitos

- Linux.
- Bash.
- Permisos de root para instalar.
- `zip` instalado. El instalador intenta instalarlo automáticamente si el sistema usa `apt-get`.
- La carpeta fuente debe existir:

  ```text
  /root/.openclaw
  ```

## Instalación sin clonar el repo

Puedes descargar y ejecutar solo `install.sh`.

### Opción 1: descargar el instalador y ejecutarlo

```bash
curl -fsSL -o install-openclaw-backup.sh https://raw.githubusercontent.com/promadeweb/openclaw-backup-system/main/install.sh
chmod +x install-openclaw-backup.sh
sudo ./install-openclaw-backup.sh
```

### Opción 2: ejecutarlo directamente desde la URL

```bash
curl -fsSL https://raw.githubusercontent.com/promadeweb/openclaw-backup-system/main/install.sh | sudo bash
```

> Nota: si el repositorio es privado, la URL raw pública no funcionará sin autenticación. En ese caso descarga `install.sh` desde GitHub o copia el archivo manualmente al servidor y ejecútalo con `sudo bash install.sh`.

El instalador preguntará:

```text
Install the backup script into which directory? [/usr/local/bin]:
Where should backups be stored? [/var/backups/openclaw]:
```

Puedes presionar ENTER para usar los valores por defecto. Si lo ejecutas en un entorno no interactivo, el instalador usará automáticamente los valores por defecto.

## Instalación desde el repo clonado

También puedes instalar desde una copia local del repositorio:

```bash
chmod +x install.sh
sudo ./install.sh
```

Ya no es necesario que `backup-openclaw.sh` esté presente junto al instalador, porque `install.sh` es autocontenido.

## Valores por defecto

| Configuración | Valor |
| --- | --- |
| Script instalado | `/usr/local/bin/backup-openclaw.sh` |
| Carpeta de backups | `/var/backups/openclaw` |
| Carpeta de logs | `/var/log/openclaw-backups` |
| Archivo de log | `/var/log/openclaw-backups/openclaw-backup.log` |
| Cron | `/etc/cron.d/openclaw-backup` |
| Logrotate | `/etc/logrotate.d/openclaw-backup` |
| Hora de ejecución | Todos los días a las `05:30` |
| Backups retenidos | `10` |
| Grupo administrador | `sudo`, `wheel` o `root` como fallback |

## Ejecución manual

Después de instalar, puedes ejecutar el backup manualmente con:

```bash
sudo /usr/local/bin/backup-openclaw.sh
```

Si elegiste otro directorio de instalación, usa la ruta correspondiente.

## Ver logs

Los usuarios del grupo administrador pueden leer el log directamente:

```bash
tail -f /var/log/openclaw-backups/openclaw-backup.log
```

También puedes verlo con sudo:

```bash
sudo tail -f /var/log/openclaw-backups/openclaw-backup.log
```

## Estructura esperada de backups

Ejemplo:

```text
/var/backups/openclaw/
├── 2026.04.23-OpenClaw.zip
├── 2026.04.24-OpenClaw.zip
├── 2026.04.25-OpenClaw.zip
└── 2026.04.26-OpenClaw/
    └── .openclaw/
```

El backup del día queda como carpeta normal. Los backups anteriores se comprimen automáticamente.

## Permisos

El instalador detecta el grupo administrador disponible en este orden:

1. `sudo`
2. `wheel`
3. `root` como fallback

Los directorios principales quedan con propietario `root:<grupo-admin>` y permisos `750`, para que root pueda escribir y el grupo administrador pueda entrar/listar:

```text
/usr/local/bin
/var/backups/openclaw
/var/log/openclaw-backups
```

El script instalado queda como `root:<grupo-admin>` con permisos `750`.

Los logs y archivos `.zip` quedan como `root:<grupo-admin>` con permisos `640`, para que root pueda escribir y el grupo administrador pueda leer.

Los directorios de backups quedan sin permisos para otros usuarios y con lectura/listado para el grupo administrador.

## Cambiar la carpeta de backup

La forma recomendada es volver a ejecutar el instalador:

```bash
sudo ./install-openclaw-backup.sh
```

Cuando pregunte por el destino de backups, indica la nueva ruta.

El instalador modifica la copia instalada del script y deja configurado cron con esa ruta.

## Cambiar la carpeta fuente

Por defecto se respalda:

```bash
SOURCE_DIR="/root/.openclaw"
```

Si OpenClaw usa otra ubicación, edita el script instalado:

```bash
sudo nano /usr/local/bin/backup-openclaw.sh
```

Y cambia `SOURCE_DIR` al path correcto.

## Cambiar la hora del backup

Edita el archivo de cron:

```bash
sudo nano /etc/cron.d/openclaw-backup
```

Por defecto contiene:

```cron
30 5 * * * root /usr/local/bin/backup-openclaw.sh
```

Esto ejecuta el backup todos los días a las 05:30.

## Logrotate

El instalador crea esta configuración en `/etc/logrotate.d/openclaw-backup`:

```text
/var/log/openclaw-backups/openclaw-backup.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root <grupo-admin>
}
```

Esto rota los logs diariamente, conserva 14 rotaciones comprimidas y mantiene los logs legibles por el grupo administrador.

## Reinstalación

El instalador es idempotente. Puedes ejecutarlo varias veces:

```bash
sudo ./install-openclaw-backup.sh
```

Al reinstalar, se sobrescriben:

- La copia instalada de `backup-openclaw.sh`.
- `/etc/cron.d/openclaw-backup`.
- `/etc/logrotate.d/openclaw-backup`.

## Solución de problemas

### El backup falla porque no existe la fuente

Verifica que exista:

```bash
sudo ls -la /root/.openclaw
```

Si OpenClaw usa otra ubicación, actualiza `SOURCE_DIR` en el script instalado.

### No se crean backups automáticamente

Revisa que el archivo de cron exista:

```bash
sudo cat /etc/cron.d/openclaw-backup
```

Luego revisa logs del sistema cron según tu distribución.

### No puedo ver los backups como usuario sudoer

Verifica tu grupo:

```bash
groups
```

Luego revisa permisos:

```bash
ls -ld /var/backups/openclaw /var/log/openclaw-backups
ls -la /var/backups/openclaw
```

Si el grupo fue actualizado recientemente, cierra sesión y vuelve a entrar para que el sistema refresque tu membresía de grupos.

### No se comprimen backups antiguos

Verifica que `zip` esté instalado:

```bash
zip --version
```

En Debian/Ubuntu puedes instalarlo con:

```bash
sudo apt-get update
sudo apt-get install -y zip
```

## Desinstalación

Para remover la instalación:

```bash
sudo rm -f /usr/local/bin/backup-openclaw.sh
sudo rm -f /etc/cron.d/openclaw-backup
sudo rm -f /etc/logrotate.d/openclaw-backup
```

Los backups y logs no se eliminan automáticamente. Si también deseas eliminarlos:

```bash
sudo rm -rf /var/backups/openclaw
sudo rm -rf /var/log/openclaw-backups
```
