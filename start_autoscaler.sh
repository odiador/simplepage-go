#!/usr/bin/env bash

#############################################
# Script de Inicio Rápido del Auto-Scaler
# Valida y ejecuta el auto-scaler
#############################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#############################################
# Banner
#############################################

show_banner() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║         🤖 AUTO-SCALER - INICIO RÁPIDO               ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_menu() {
    echo -e "${BLUE}Selecciona el modo de operación:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Validar configuración primero (recomendado)"
    echo -e "  ${GREEN}2)${NC} Iniciar auto-scaler en modo normal"
    echo -e "  ${GREEN}3)${NC} Iniciar auto-scaler en modo prueba (con stress artificial)"
    echo -e "  ${GREEN}4)${NC} Iniciar con configuración personalizada"
    echo -e "  ${GREEN}5)${NC} Ver ayuda completa"
    echo -e "  ${GREEN}6)${NC} Salir"
    echo ""
}

run_validation() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Ejecutando validación...${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -x "$SCRIPT_DIR/validate_autoscaler.sh" ]; then
        "$SCRIPT_DIR/validate_autoscaler.sh"
        return $?
    else
        echo -e "${RED}❌ validate_autoscaler.sh no encontrado o no es ejecutable${NC}"
        return 1
    fi
}

run_autoscaler_normal() {
    echo ""
    echo -e "${GREEN}🚀 Iniciando auto-scaler en modo NORMAL...${NC}"
    echo ""
    echo -e "${YELLOW}Presiona Ctrl+C para detener${NC}"
    echo ""
    sleep 2
    
    if [ -x "$SCRIPT_DIR/autoscaler.sh" ]; then
        "$SCRIPT_DIR/autoscaler.sh"
    else
        echo -e "${RED}❌ autoscaler.sh no encontrado o no es ejecutable${NC}"
        exit 1
    fi
}

run_autoscaler_test() {
    echo ""
    echo -e "${GREEN}🧪 Iniciando auto-scaler en modo PRUEBA...${NC}"
    echo ""
    echo -e "${YELLOW}Este modo generará carga artificial en el balanceador${NC}"
    echo -e "${YELLOW}Asegúrate de que stress-ng esté instalado en el balanceador${NC}"
    echo ""
    echo -e "${YELLOW}Presiona Ctrl+C para detener${NC}"
    echo ""
    sleep 3
    
    if [ -x "$SCRIPT_DIR/autoscaler.sh" ]; then
        "$SCRIPT_DIR/autoscaler.sh" --modo-prueba
    else
        echo -e "${RED}❌ autoscaler.sh no encontrado o no es ejecutable${NC}"
        exit 1
    fi
}

run_autoscaler_custom() {
    echo ""
    echo -e "${BLUE}⚙️  Configuración personalizada${NC}"
    echo ""
    
    read -p "Umbral alto de CPU (default: 75): " umbral_alto
    umbral_alto=${umbral_alto:-75}
    
    read -p "Umbral crítico de CPU (default: 85): " umbral_critico
    umbral_critico=${umbral_critico:-85}
    
    read -p "Umbral bajo de CPU (default: 40): " umbral_bajo
    umbral_bajo=${umbral_bajo:-40}
    
    read -p "Mínimo de servidores (default: 2): " min_servers
    min_servers=${min_servers:-2}
    
    read -p "Máximo de servidores (default: 5): " max_servers
    max_servers=${max_servers:-5}
    
    read -p "Intervalo de monitoreo en segundos (default: 20): " intervalo
    intervalo=${intervalo:-20}
    
    read -p "Tiempo de cooldown en segundos (default: 60): " cooldown
    cooldown=${cooldown:-60}
    
    echo ""
    echo -e "${BLUE}Configuración:${NC}"
    echo "  • Umbral alto: ${umbral_alto}%"
    echo "  • Umbral crítico: ${umbral_critico}%"
    echo "  • Umbral bajo: ${umbral_bajo}%"
    echo "  • Min servidores: ${min_servers}"
    echo "  • Max servidores: ${max_servers}"
    echo "  • Intervalo: ${intervalo}s"
    echo "  • Cooldown: ${cooldown}s"
    echo ""
    
    read -p "¿Modo prueba? (s/N): " modo_prueba
    
    echo ""
    echo -e "${GREEN}🚀 Iniciando auto-scaler...${NC}"
    echo -e "${YELLOW}Presiona Ctrl+C para detener${NC}"
    echo ""
    sleep 2
    
    local args=(
        "--umbral-alto" "$umbral_alto"
        "--umbral-critico" "$umbral_critico"
        "--umbral-bajo" "$umbral_bajo"
        "--min-servidores" "$min_servers"
        "--max-servidores" "$max_servers"
        "--intervalo" "$intervalo"
        "--cooldown" "$cooldown"
    )
    
    if [[ "$modo_prueba" =~ ^[Ss]$ ]]; then
        args+=("--modo-prueba")
    fi
    
    if [ -x "$SCRIPT_DIR/autoscaler.sh" ]; then
        "$SCRIPT_DIR/autoscaler.sh" "${args[@]}"
    else
        echo -e "${RED}❌ autoscaler.sh no encontrado o no es ejecutable${NC}"
        exit 1
    fi
}

show_help() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  AYUDA COMPLETA${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -x "$SCRIPT_DIR/autoscaler.sh" ]; then
        "$SCRIPT_DIR/autoscaler.sh" --help
    else
        echo -e "${RED}❌ autoscaler.sh no encontrado${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Documentación completa: AUTOSCALER.md${NC}"
    echo ""
}

#############################################
# Main
#############################################

main() {
    show_banner
    
    while true; do
        show_menu
        read -p "Opción [1-6]: " option
        
        case $option in
            1)
                if run_validation; then
                    echo ""
                    read -p "¿Continuar e iniciar el auto-scaler? (S/n): " continue
                    if [[ ! "$continue" =~ ^[Nn]$ ]]; then
                        run_autoscaler_normal
                    fi
                else
                    echo ""
                    echo -e "${RED}Corrige los errores antes de continuar${NC}"
                    read -p "Presiona Enter para continuar..."
                fi
                ;;
            2)
                run_autoscaler_normal
                ;;
            3)
                run_autoscaler_test
                ;;
            4)
                run_autoscaler_custom
                ;;
            5)
                show_help
                read -p "Presiona Enter para continuar..."
                ;;
            6)
                echo ""
                echo -e "${GREEN}👋 ¡Hasta luego!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo -e "${RED}❌ Opción inválida${NC}"
                sleep 1
                ;;
        esac
        
        # Si llegamos aquí después de ejecutar el autoscaler, preguntar si reiniciar
        echo ""
        read -p "¿Volver al menú principal? (S/n): " restart
        if [[ "$restart" =~ ^[Nn]$ ]]; then
            echo ""
            echo -e "${GREEN}👋 ¡Hasta luego!${NC}"
            echo ""
            exit 0
        fi
        
        clear
        show_banner
    done
}

# Manejo de argumentos
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

main
