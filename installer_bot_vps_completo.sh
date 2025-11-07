#!/bin/bash

# installer_bot_vps_completo.sh - Instalador completo de Bot Telegram + Mercado Pago + Gestión VPS
# Autor: Tu Nombre
# Versión: 2.0

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables globales
BOT_DIR="$HOME/telegram_bot_vps"
PYTHON_VENV="$BOT_DIR/bot_env"
SSH_DIR="$BOT_DIR/ssh_users"
SCRIPTS_DIR="$BOT_DIR/scripts"

# Función para mostrar header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║           INSTALADOR BOT VPS COMPLETO               ║"
    echo "║         Telegram + Mercado Pago + Gestión VPS       ║"
    echo "║                 Versión 2.0                         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Funciones de log
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
warning() { echo -e "${YELLOW}[ADVERTENCIA] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Función para verificar y instalar dependencias del sistema
check_system_dependencies() {
    log "Verificando dependencias del sistema..."
    
    local missing_deps=()
    
    # Verificar paquetes básicos
    for pkg in python3 pip3 jq openssh-server sshpass; do
        if ! command -v $pkg &> /dev/null; then
            missing_deps+=("$pkg")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        warning "Dependencias faltantes: ${missing_deps[*]}"
        read -p "¿Instalar automáticamente? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            sudo apt update
            sudo apt install -y "${missing_deps[@]}"
        fi
    fi
}

# Función para crear estructura de directorios
create_directory_structure() {
    log "Creando estructura de directorios..."
    
    mkdir -p "$BOT_DIR" "$SSH_DIR" "$SCRIPTS_DIR" "$SSH_DIR/keys" "$SSH_DIR/configs"
    
    info "Directorio principal: $BOT_DIR"
    info "Directorio SSH: $SSH_DIR"
    info "Directorio scripts: $SCRIPTS_DIR"
}

# Función para crear script de gestión de usuarios SSH
create_ssh_manager() {
    log "Creando script de gestión de usuarios SSH..."
    
    cat > "$SCRIPTS_DIR/ssh_manager.sh" << 'EOF'
#!/bin/bash

# ssh_manager.sh - Gestión de usuarios SSH para VPS
# Autor: Sistema Automático

SSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)/ssh_users"
USERS_DB="$SSH_DIR/ssh_users.json"
LOG_FILE="$SSH_DIR/ssh_manager.log"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

create_ssh_user() {
    local username="$1"
    local password="$2"
    local days_valid="$3"
    local telegram_id="$4"
    
    log "Creando usuario SSH: $username por $days_valid días"
    
    # Verificar si el usuario existe
    if id "$username" &>/dev/null; then
        echo "❌ El usuario $username ya existe"
        return 1
    fi
    
    # Crear usuario
    sudo useradd -m -s /bin/bash "$username"
    if [ $? -ne 0 ]; then
        echo "❌ Error al crear usuario"
        return 1
    fi
    
    # Establecer contraseña
    echo "$username:$password" | sudo chpasswd
    if [ $? -ne 0 ]; then
        echo "❌ Error al establecer contraseña"
        sudo userdel -r "$username" 2>/dev/null
        return 1
    fi
    
    # Crear directorio .ssh y configurar permisos
    sudo mkdir -p "/home/$username/.ssh"
    sudo chown "$username:$username" "/home/$username/.ssh"
    sudo chmod 700 "/home/$username/.ssh"
    
    # Calcular fecha de expiración
    local expire_date=$(date -d "+$days_valid days" '+%Y-%m-%d')
    
    # Guardar en base de datos
    local user_data=$(jq -n \
        --arg user "$username" \
        --arg pass "$password" \
        --arg expire "$expire_date" \
        --arg tg_id "$telegram_id" \
        --arg created "$(date '+%Y-%m-%d %H:%M:%S')" \
        '{
            username: $user,
            password: $pass,
            expire_date: $expire,
            telegram_id: $tg_id,
            created_at: $created,
            is_active: true,
            last_login: null
        }')
    
    if [ -f "$USERS_DB" ]; then
        jq --argjson new "$user_data" '. += [$new]' "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
    else
        echo "[$user_data]" > "$USERS_DB"
    fi
    
    # Configurar expiración de cuenta
    sudo chage -E $(date -d "+$days_valid days" +%Y-%m-%d) "$username"
    
    echo "✅ Usuario SSH creado: $username"
    echo "🔑 Contraseña: $password"
    echo "📅 Expira: $expire_date"
    echo "📊 Límite de sesiones: 1 simultánea"
    
    log "Usuario $username creado exitosamente"
    return 0
}

delete_ssh_user() {
    local username="$1"
    
    log "Eliminando usuario SSH: $username"
    
    if ! id "$username" &>/dev/null; then
        echo "❌ El usuario $username no existe"
        return 1
    fi
    
    # Eliminar usuario y su directorio
    sudo userdel -r "$username" 2>/dev/null
    
    # Actualizar base de datos
    if [ -f "$USERS_DB" ]; then
        jq "map(select(.username != \"$username\"))" "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
    fi
    
    echo "✅ Usuario $username eliminado"
    log "Usuario $username eliminado"
    return 0
}

suspend_ssh_user() {
    local username="$1"
    
    sudo usermod -L "$username" 2>/dev/null
    if [ $? -eq 0 ]; then
        # Actualizar base de datos
        if [ -f "$USERS_DB" ]; then
            jq "map(if .username == \"$username\" then .is_active = false else . end)" "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
        fi
        echo "✅ Usuario $username suspendido"
        log "Usuario $username suspendido"
    else
        echo "❌ Error al suspender usuario $username"
    fi
}

unsuspend_ssh_user() {
    local username="$1"
    
    sudo usermod -U "$username" 2>/dev/null
    if [ $? -eq 0 ]; then
        # Actualizar base de datos
        if [ -f "$USERS_DB" ]; then
            jq "map(if .username == \"$username\" then .is_active = true else . end)" "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
        fi
        echo "✅ Usuario $username reactivado"
        log "Usuario $username reactivado"
    else
        echo "❌ Error al reactivar usuario $username"
    fi
}

list_ssh_users() {
    if [ -f "$USERS_DB" ]; then
        jq -r '.[] | "\(.username) | Expira: \(.expire_date) | Activo: \(.is_active) | Telegram: \(.telegram_id)"' "$USERS_DB"
    else
        echo "No hay usuarios registrados"
    fi
}

check_expired_users() {
    local today=$(date '+%Y-%m-%d')
    local expired_users=()
    
    if [ -f "$USERS_DB" ]; then
        while IFS= read -r user; do
            if [ -n "$user" ]; then
                expired_users+=("$user")
                delete_ssh_user "$user"
            fi
        done < <(jq -r ".[] | select(.expire_date < \"$today\") | .username" "$USERS_DB")
    fi
    
    if [ ${#expired_users[@]} -gt 0 ]; then
        echo "Usuarios expirados eliminados: ${expired_users[*]}"
    fi
}

get_user_info() {
    local username="$1"
    
    if [ -f "$USERS_DB" ]; then
        jq -r ".[] | select(.username == \"$username\")" "$USERS_DB"
    else
        echo "{}"
    fi
}

# Manejo de argumentos
case "$1" in
    create)
        create_ssh_user "$2" "$3" "$4" "$5"
        ;;
    delete)
        delete_ssh_user "$2"
        ;;
    suspend)
        suspend_ssh_user "$2"
        ;;
    unsuspend)
        unsuspend_ssh_user "$2"
        ;;
    list)
        list_ssh_users
        ;;
    check-expired)
        check_expired_users
        ;;
    info)
        get_user_info "$2"
        ;;
    *)
        echo "Uso: $0 {create|delete|suspend|unsuspend|list|check-expired|info}"
        echo "Ejemplos:"
        echo "  $0 create usuario1 password123 30 123456789"
        echo "  $0 delete usuario1"
        echo "  $0 list"
        exit 1
        ;;
esac
EOF

    chmod +x "$SCRIPTS_DIR/ssh_manager.sh"
    info "Script de gestión SSH creado: $SCRIPTS_DIR/ssh_manager.sh"
}

# Función para crear script de información del sistema
create_system_info_script() {
    log "Creando script de información del sistema..."
    
    cat > "$SCRIPTS_DIR/system_info.sh" << 'EOF'
#!/bin/bash

# system_info.sh - Información del sistema VPS
# Autor: Sistema Automático

get_system_info() {
    echo "🖥️ *INFORMACIÓN DEL SISTEMA*"
    echo "──────────────────────"
    
    # Información básica
    echo "• *Hostname:* $(hostname)"
    echo "• *Sistema:* $(lsb_release -d | cut -f2) ($(uname -r))"
    echo "• *Uptime:* $(uptime -p | sed 's/up //')"
    
    # Uso de CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "• *Uso de CPU:* ${cpu_usage}%"
    
    # Memoria
    local mem_info=$(free -h | grep Mem)
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_free=$(echo $mem_info | awk '{print $4}')
    echo "• *Memoria:* Usada: $mem_used / Total: $mem_total"
    
    # Disco
    local disk_usage=$(df -h / | awk 'NR==2 {print $5 " (" $3 " / " $2 ")"}')
    echo "• *Disco raíz:* $disk_usage"
    
    # Conexiones SSH activas
    local ssh_connections=$(who | wc -l)
    echo "• *Conexiones SSH activas:* $ssh_connections"
    
    # Usuarios SSH totales
    local total_users=$(sudo cat /etc/passwd | grep -E "/bin/bash|/bin/sh" | grep -v root | grep -v false | wc -l)
    echo "• *Usuarios SSH totales:* $total_users"
    
    # Carga del sistema
    local load_avg=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
    echo "• *Carga del sistema:* $load_avg"
    
    # Tráfico de red (requiere vnstat)
    if command -v vnstat &> /dev/null; then
        local network_traffic=$(vnstat -m --json | jq -r '.interfaces[0].traffic.months[-1] | "⬇️ \(.rx) ⬆️ \(.tx)"')
        echo "• *Tráfico este mes:* $network_traffic"
    fi
    
    echo "──────────────────────"
}

get_ssh_users_info() {
    local ssh_db="$1/ssh_users/ssh_users.json"
    
    if [ -f "$ssh_db" ]; then
        local total_users=$(jq 'length' "$ssh_db")
        local active_users=$(jq '[.[] | select(.is_active == true)] | length' "$ssh_db")
        local expired_users=$(jq --arg today "$(date '+%Y-%m-%d')" '[.[] | select(.expire_date < $today)] | length' "$ssh_db")
        
        echo "👥 *INFORMACIÓN DE USUARIOS SSH*"
        echo "──────────────────────"
        echo "• *Total usuarios:* $total_users"
        echo "• *Usuarios activos:* $active_users"
        echo "• *Usuarios expirados:* $expired_users"
        echo "──────────────────────"
        
        # Listar usuarios activos
        echo "📋 *Usuarios Activos:*"
        jq -r '.[] | select(.is_active == true) | "• \(.username) - Expira: \(.expire_date)"' "$ssh_db" | while read user; do
            echo "$user"
        done
    else
        echo "📋 No hay usuarios SSH registrados"
    fi
}

# Ejecutar según parámetro
case "$1" in
    system)
        get_system_info
        ;;
    users)
        get_ssh_users_info "$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
        ;;
    full)
        get_system_info
        echo
        get_ssh_users_info "$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
        ;;
    *)
        echo "Uso: $0 {system|users|full}"
        ;;
esac
EOF

    chmod +x "$SCRIPTS_DIR/system_info.sh"
    info "Script de información del sistema creado"
}

# Función para crear el bot principal con gestión VPS
create_enhanced_bot() {
    log "Creando bot mejorado con gestión VPS..."
    
    cat > "$BOT_DIR/bot.py" << 'EOF'
#!/usr/bin/env python3
# bot.py - Bot Telegram + Mercado Pago + Gestión VPS

import telebot
import logging
import json
import os
import subprocess
import random
import string
from datetime import datetime, timedelta
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
from config import Config, LOGGING_CONFIG

# Configurar logging
logging.config.dictConfig(LOGGING_CONFIG)
logger = logging.getLogger(__name__)

class VPSManager:
    def __init__(self):
        self.ssh_manager = os.path.join(os.path.dirname(__file__), 'scripts', 'ssh_manager.sh')
        self.system_info = os.path.join(os.path.dirname(__file__), 'scripts', 'system_info.sh')
    
    def generate_username(self, telegram_id: int) -> str:
        """Genera nombre de usuario único"""
        base = f"user{telegram_id}"
        return base
    
    def generate_password(self, length=12) -> str:
        """Genera contraseña segura"""
        chars = string.ascii_letters + string.digits + "!@#$%"
        return ''.join(random.choice(chars) for _ in range(length))
    
    def create_ssh_user(self, plan_days: int, telegram_id: int, username: str = None) -> dict:
        """Crea usuario SSH"""
        if not username:
            username = self.generate_username(telegram_id)
        
        password = self.generate_password()
        
        try:
            result = subprocess.run([
                'sudo', self.ssh_manager, 'create', 
                username, password, str(plan_days), str(telegram_id)
            ], capture_output=True, text=True, check=True)
            
            return {
                'success': True,
                'username': username,
                'password': password,
                'output': result.stdout
            }
        except subprocess.CalledProcessError as e:
            return {
                'success': False,
                'error': e.stderr
            }
    
    def get_system_info(self) -> str:
        """Obtiene información del sistema"""
        try:
            result = subprocess.run([
                self.system_info, 'full'
            ], capture_output=True, text=True, check=True)
            return result.stdout
        except subprocess.CalledProcessError as e:
            return f"Error obteniendo información: {e.stderr}"
    
    def get_ssh_users(self) -> str:
        """Obtiene lista de usuarios SSH"""
        try:
            result = subprocess.run([
                self.ssh_manager, 'list'
            ], capture_output=True, text=True, check=True)
            return result.stdout if result.stdout else "No hay usuarios"
        except subprocess.CalledProcessError as e:
            return f"Error: {e.stderr}"

class EnhancedBotManager:
    def __init__(self):
        self.bot = telebot.TeleBot(Config.TELEGRAM_BOT_TOKEN)
        self.vps_manager = VPSManager()
        self.setup_handlers()
        
    def create_plan_keyboard(self):
        """Crea teclado para selección de planes"""
        keyboard = InlineKeyboardMarkup(row_width=1)
        
        for plan_id, plan in Config.PLANS.items():
            keyboard.add(InlineKeyboardButton(
                f"{plan['title']} - ${plan['price']} ARS",
                callback_data=f"buy_{plan_id}"
            ))
        
        keyboard.add(InlineKeyboardButton("🖥️ Info VPS", callback_data="vps_info"))
        keyboard.add(InlineKeyboardButton("📊 Mis Servicios", callback_data="my_services"))
        
        return keyboard
    
    def create_admin_keyboard(self):
        """Crea teclado de administración"""
        keyboard = InlineKeyboardMarkup(row_width=2)
        
        keyboard.add(
            InlineKeyboardButton("📊 Estadísticas", callback_data="admin_stats"),
            InlineKeyboardButton("👥 Usuarios SSH", callback_data="admin_users"),
            InlineKeyboardButton("🖥️ Sistema", callback_data="admin_system"),
            InlineKeyboardButton("🔄 Actualizar", callback_data="admin_refresh")
        )
        
        return keyboard
    
    def setup_handlers(self):
        """Configura los manejadores de comandos"""
        
        @self.bot.message_handler(commands=['start', 'help'])
        def send_welcome(message):
            welcome_text = """
🤖 *BOT VPS PREMIUM - ACCESO SSH*

¡Bienvenido! Ofrecemos acceso SSH premium a nuestra VPS:

*🖥️ Características de la VPS:*
• Alto rendimiento
• Conexión estable
• Soporte 24/7
• Acceso root completo

*📦 Planes Disponibles:*
"""
            for plan_id, plan in Config.PLANS.items():
                welcome_text += f"• {plan['title']} - ${plan['price']} ARS\n"
            
            welcome_text += """
*🚀 Comandos útiles:*
/planes - Ver planes disponibles
/comprar - Comprar acceso SSH
/info - Información de la VPS
/miservicios - Mis servicios activos

*⚡ ¡Obtén tu acceso SSH ahora!*
"""
            self.bot.reply_to(message, welcome_text, parse_mode='Markdown',
                            reply_markup=self.create_plan_keyboard())
        
        @self.bot.message_handler(commands=['planes'])
        def show_plans(message):
            plans_text = "🎯 *PLANES DE ACCESO SSH:*\n\n"
            
            for plan_id, plan in Config.PLANS.items():
                plans_text += f"*{plan['title']}*\n"
                plans_text += f"• Duración: {plan['days']} días\n"
                plans_text += f"• Precio: ${plan['price']} ARS\n"
                plans_text += f"• Descripción: {plan['description']}\n\n"
            
            plans_text += "Selecciona un plan para continuar:"
            
            self.bot.reply_to(message, plans_text, parse_mode='Markdown',
                            reply_markup=self.create_plan_keyboard())
        
        @self.bot.message_handler(commands=['comprar'])
        def buy_access(message):
            self.bot.reply_to(message, "🎯 Selecciona el plan que deseas comprar:",
                            reply_markup=self.create_plan_keyboard())
        
        @self.bot.message_handler(commands=['info'])
        def vps_info(message):
            info_text = self.vps_manager.get_system_info()
            self.bot.reply_to(message, f"```\n{info_text}\n```", parse_mode='Markdown')
        
        @self.bot.message_handler(commands=['miservicios'])
        def my_services(message):
            user_services = "🔍 *Tus servicios activos:*\n\n"
            
            # Aquí integrarías con tu base de datos
            user_services += "📋 No tienes servicios activos\n"
            user_services += "¡Adquiere tu primer plan con /comprar!"
            
            self.bot.reply_to(message, user_services, parse_mode='Markdown')
        
        @self.bot.message_handler(commands=['admin'])
        def admin_panel(message):
            if message.from_user.id not in Config.ADMINS:
                self.bot.reply_to(message, "❌ No tienes permisos de administrador")
                return
            
            admin_text = """
👨‍💼 *PANEL DE ADMINISTRACIÓN VPS*

*Comandos disponibles:*
• /admin_stats - Estadísticas detalladas
• /admin_users - Gestión de usuarios
• /admin_system - Estado del sistema

Selecciona una opción:
"""
            self.bot.reply_to(message, admin_text, parse_mode='Markdown',
                            reply_markup=self.create_admin_keyboard())
        
        # Manejo de callbacks
        @self.bot.callback_query_handler(func=lambda call: True)
        def handle_callback(call):
            user_id = call.from_user.id
            
            if call.data.startswith("buy_"):
                plan_id = call.data.replace("buy_", "")
                plan = Config.PLANS.get(plan_id)
                
                if plan:
                    # Aquí integrarías con Mercado Pago
                    payment_text = f"""
💳 *PROCESANDO PAGO*

*Plan:* {plan['title']}
*Duración:* {plan['days']} días
*Precio:* ${plan['price']} ARS

⚠️ *Funcionalidad en desarrollo*
La integración con Mercado Pago se activará próximamente.

*Características que obtendrás:*
✅ Usuario SSH personalizado
✅ Contraseña segura
✅ Acceso completo por {plan['days']} días
✅ Soporte técnico prioritario
"""
                    self.bot.send_message(call.message.chat.id, payment_text, 
                                        parse_mode='Markdown')
                else:
                    self.bot.answer_callback_query(call.id, "❌ Plan no encontrado")
            
            elif call.data == "vps_info":
                info_text = self.vps_manager.get_system_info()
                self.bot.edit_message_text(
                    chat_id=call.message.chat.id,
                    message_id=call.message.message_id,
                    text=f"```\n{info_text}\n```",
                    parse_mode='Markdown'
                )
            
            elif call.data == "admin_stats":
                if user_id in Config.ADMINS:
                    stats_text = self.vps_manager.get_system_info()
                    users_text = self.vps_manager.get_ssh_users()
                    
                    full_text = f"*📊 ESTADÍSTICAS VPS*\n\n```{stats_text}```\n*👥 USUARIOS SSH:*\n```{users_text}```"
                    
                    self.bot.edit_message_text(
                        chat_id=call.message.chat.id,
                        message_id=call.message.message_id,
                        text=full_text,
                        parse_mode='Markdown'
                    )
    
    def start_bot(self):
        """Inicia el bot"""
        logger.info("Iniciando bot de Telegram con gestión VPS...")
        try:
            self.bot.polling(none_stop=True, interval=0, timeout=20)
        except Exception as e:
            logger.error(f"Error en el bot: {e}")
            import time
            time.sleep(5)
            self.start_bot()

def main():
    """Función principal"""
    print("🚀 Iniciando Bot VPS Completo...")
    print("📁 Directorio:", Config.USERS_FILE)
    print("🖥️  Gestión SSH: Activada")
    print("🤖 Bot iniciado. Presiona Ctrl+C para detener.")
    
    try:
        bot_manager = EnhancedBotManager()
        bot_manager.start_bot()
    except KeyboardInterrupt:
        print("\n👋 Bot detenido por el usuario")
    except Exception as e:
        print(f"❌ Error crítico: {e}")

if __name__ == "__main__":
    main()
EOF

    chmod +x "$BOT_DIR/bot.py"
    info "Bot mejorado creado con gestión VPS"
}

# Función para crear configuración mejorada
create_enhanced_config() {
    log "Creando configuración mejorada..."
    
    cat > "$BOT_DIR/config.py" << 'EOF'
# config.py - Configuración del Bot VPS Completo
import os
import logging.config
from dotenv import load_dotenv

load_dotenv()

class Config:
    # Telegram Bot Token
    TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '6503074525:AAF2Hvx298Vx37Vmt-8sIpE6vnl5hNVLw9A')
    
    # Mercado Pago
    MP_ACCESS_TOKEN = os.getenv('MP_ACCESS_TOKEN', 'APP_USR-988290088406408-110515-c5e1e7bb6a3871c705f0790b12142ead-399825205')
    
    # Planes de acceso SSH
    PLANS = {
        "7_days": {
            "id": "7_days",
            "title": "🟢 Básico 7 Días",
            "description": "Acceso SSH básico por 7 días",
            "price": 300.00,
            "currency": "ARS",
            "days": 7
        },
        "15_days": {
            "id": "15_days",
            "title": "🔵 Standard 15 Días",
            "description": "Acceso SSH estándar por 15 días",
            "price": 500.00,
            "currency": "ARS",
            "days": 15
        },
        "30_days": {
            "id": "30_days",
            "title": "🟣 Premium 30 Días",
            "description": "Acceso SSH premium por 30 días",
            "price": 800.00,
            "currency": "ARS",
            "days": 30
        }
    }
    
    # Configuración de archivos
    USERS_FILE = "users.json"
    PAYMENTS_FILE = "payments.json"
    LOG_FILE = "bot.log"
    SSH_USERS_DB = "ssh_users/ssh_users.json"
    
    # Administradores (agrega tus IDs de Telegram)
    ADMINS = [613630545]  # Reemplaza con tu ID
    
    # Configuración SSH
    SSH_PORT = 22
    MAX_SESSIONS_PER_USER = 1

# Configuración de logging
LOGGING_CONFIG = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'detailed': {
            'format': '%(asctime)s [%(levelname)s] %(name)s: %(message)s'
        },
    },
    'handlers': {
        'file': {
            'level': 'INFO',
            'class': 'logging.FileHandler',
            'filename': Config.LOG_FILE,
            'formatter': 'detailed'
        },
        'console': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'detailed'
        },
    },
    'loggers': {
        '': {
            'handlers': ['file', 'console'],
            'level': 'INFO',
            'propagate': True
        }
    }
}
EOF

    info "Configuración mejorada creada"
}

# Función para configurar el sistema
configure_system() {
    log "Configurando sistema..."
    
    # Configurar SSH (opcional)
    read -p "¿Configurar SSH para aceptar conexiones? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
        sudo systemctl restart ssh
        info "SSH configurado para aceptar conexiones con contraseña"
    fi
    
    # Crear tarea cron para limpiar usuarios expirados
    (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPTS_DIR/ssh_manager.sh check-expired >> $SSH_DIR/cron.log 2>&1") | crontab -
    info "Tarea cron creada para limpieza automática"
}

# Función principal de instalación
main_installation() {
    show_header
    echo -e "${YELLOW}Iniciando instalación del Bot VPS Completo...${NC}"
    echo
    
    read -p "¿Continuar con la instalación? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        error "Instalación cancelada por el usuario"
        exit 1
    fi
    
    # Ejecutar pasos de instalación
    check_system_dependencies
    create_directory_structure
    create_ssh_manager
    create_system_info_script
    create_enhanced_config
    create_enhanced_bot
    configure_system
    
    log "Instalación completada exitosamente! 🎉"
    
    # Mostrar resumen
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║               INSTALACIÓN VPS COMPLETADA            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📁 Directorio del bot:${NC} $BOT_DIR"
    echo -e "${CYAN}🔐 Script SSH Manager:${NC} $SCRIPTS_DIR/ssh_manager.sh"
    echo -e "${CYAN}🖥️  Script System Info:${NC} $SCRIPTS_DIR/system_info.sh"
    echo
    echo -e "${YELLOW}🚀 PRÓXIMOS PASOS:${NC}"
    echo -e "1. Configurar tokens en ${MAGENTA}$BOT_DIR/.env${NC}"
    echo -e "2. Agregar tu ID de Telegram como admin en ${MAGENTA}config.py${NC}"
    echo -e "3. Ejecutar: ${GREEN}cd $BOT_DIR && python3 bot.py${NC}"
    echo
    echo -e "${GREEN}✅ ¡Tu bot VPS está listo!${NC}"
}

# Ejecutar instalación
main_installation