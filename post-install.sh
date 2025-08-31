#!/bin/bash
# Habilitar serviços do RAGlinux
systemctl enable sddm
systemctl enable NetworkManager
systemctl enable cockpit.socket
systemctl enable fwupd

# Configurar usuário padrão
useradd -m -G wheel -s /bin/bash user
echo "user:user" | chpasswd

# Configurações específicas do Plasma
echo "[General]" > /etc/sddm.conf
echo "DisplayServer=wayland" >> /etc/sddm.conf
