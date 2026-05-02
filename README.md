# OpenClaw Backup System

Sistema de respaldo diario para la carpeta de datos de OpenClaw.

Este repositorio incluye un script de backup y un instalador para dejarlo configurado en un servidor Linux con cron y logrotate.

## Archivos incluidos

- `backup-openclaw.sh`: crea backups diarios de `/root/.openclaw`.
- `install.sh`: instala el script, crea directorios, configura permisos, cron y logrotate.

## Qué hace el backup

El script `backup-openclaw.sh` realiza las siguientes tareas:

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

## Requisitos

- Linux.
- Bash.
- Permisos de root para instalar.
- `zip` instalado. El instalador intenta instalarlo automáticamente si el sistema usa `apt-get`.
- La carpeta fuente debe existir:

  ```text
  /root/.openclaw
  ```

## Instalación

Desde la raíz del repositorio:

```bash
chmod +x install.sh backup-openclaw.sh
sudo ./install.sh
```

El instalador preguntará:

```text
Install the backup script into which directory? [/usr/local/bin]:
Where should backups be stored? [/var/backups/openclaw]:
```

Puedes presionar ENTER para usar los valores por defecto.

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

## Ejecución manual

Después de instalar, puedes ejecutar el backup manualmente con:

```bash
sudo /usr/local/bin/backup-openclaw.sh
```

Si elegiste otro directorio de instalación, usa la ruta correspondiente.

## Ver logs

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

## Cambiar la carpeta de backup

La forma recomendada es volver a ejecutar el instalador:

```bash
sudo ./install.sh
```

Cuando pregunte por el destino de backups, indica la nueva ruta.

El instalador modifica únicamente la copia instalada del script. El archivo `backup-openclaw.sh` del repositorio conserva sus valores por defecto.

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
    create 0640 root root
}
```

Esto rota los logs diariamente y conserva 14 rotaciones comprimidas.

## Seguridad y permisos

El instalador aplica permisos restrictivos:

- Directorio del script: `700`.
- Directorio de backups: `700`.
- Directorio de logs: `750`.
- Script instalado: `700`.
- Log: `640`.
- Cron y logrotate: `644`.

Los archivos quedan propiedad de `root:root`.

## Reinstalación

El instalador es idempotente. Puedes ejecutarlo varias veces:

```bash
sudo ./install.sh
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
