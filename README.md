
---

```markdown
# RAGLinux

RAGLinux é um sistema baseado em **Arch Linux** imutável, gerenciado com **OSTree** e construído via **Podman**. Este projeto automatiza a criação de rootfs, subvolumes Btrfs, deploy OSTree, configuração de bootloader e integração de pacotes via container.

---

## 🚀 Estrutura do projeto

```

raglinux/
├── raglinux.sh           # Script principal de instalação e gerenciamento
├── Containerfile.base    # Containerfile para criar rootfs
├── README.md             # Documentação do projeto
├── post-install.sh       # (Opcional) script pós-instalação
├── archlinux/            # Configurações específicas do Arch
├── cachyos/              # Configurações de build adicionais
└── Containerfile.host.example

````

---

## 🛠 Scripts principais

### `raglinux.sh`

- Responsável por:
  - Preparar ambiente
  - Montar partições e subvolumes Btrfs
  - Inicializar repositório OSTree
  - Criar rootfs via Podman
  - Configurar links simbólicos e tmpfiles
  - Criar commit OSTree e deploy
  - Instalar GRUB EFI e gerar `grub.cfg`

- Comandos disponíveis:
  ```bash
  ./raglinux.sh install   # Cria deployment inicial
  ./raglinux.sh upgrade   # Cria novo commit OSTree
  ./raglinux.sh revert    # Reverte para deployment 0
  ./raglinux.sh help      # Exibe documentação do CLI
````

* Opções importantes:

  ```text
  -b, --base-os      : Nome do OS (default raglinux)
  -c, --cmdline      : Kernel args
  -d, --dev          : Device SCSI para instalação
  -f, --file         : Containerfile(s) para build
  -k, --keymap       : Layout TTY
  -t, --time         : Timezone
  -m, --merge        : Retém /etc em upgrade
  -n, --no-cache     : Ignora cache (Pacman + Podman)
  -q, --quiet        : Reduz saída
  ```

---

### `Containerfile.base`

* Base para construção do rootfs
* Instala pacotes essenciais via `pacstrap`:

  * `base`, `base-devel`, `linux`, `linux-firmware`, `ostree`, `btrfs-progs`, `nano`, `git`
  * `plasma-desktop`, `konsole`, `dolphin`, `plasma-workspace`, `sddm`
  * `cockpit`, `fwupd`, `pipewire`, `wireplumber`, `bluez`, `gst-plugins-*`, `ffmpeg`
  * `podman`, `distrobox`, `bzr`, `buildah`, `skopeo`, `just`, `networkmanager`, `fastfetch`, `flatpak`
* Configura timezone e keymap
* Configura `locale` e hostname

---

## ⚠️ Problemas resolvidos durante a instalação

1. **Espaço insuficiente no LiveCD (`airootfs`)**

   * Solução: Usei `/mnt/podman` para TMPDIR e root do Podman.

   ```bash
   export TMPDIR=/mnt/podman/tmp
   ```

2. **Erro de volume Podman não encontrado**

   * Solução: Criei diretórios para cache do pacman antes do build:

   ```bash
   mkdir -p /mnt/podman/var/cache/pacman
   ```

3. **GRUB não instalado no chroot**

   * Solução: Montar `/boot` e `/ostree` dentro do deployment e usar `chroot`:

   ```bash
   for i in /dev /proc /sys; do mount -o bind $i ${DEPLOY_PATH}${i}; done
   chroot ${DEPLOY_PATH} /bin/bash -c 'grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg'
   ```

4. **Pacman inacessível no root OSTree**

   * Solução: Mantive cache e DB em `/usr/lib/pacman` e usei Podman ou Flatpak para instalar apps.

---

## 🗂 Estrutura de rootfs OSTree

```
/                   # Root imutável
/home               # Subvolume @home
/var                # Subvolume @var
/ostree             # Subvolume @ostree (deployments)
/boot/efi           # EFI boot
/usr/lib/pacman      # Pacman DB e cache
/usr/lib/tmpfiles.d  # Configuração tmpfiles
```

* Root é **imutável**
* Atualizações são via **OSTree commits**
* Rollback possível se algo der errado

---

## 🖥 Gerenciamento do sistema

* Ver deploys:

```bash
ostree admin status
```

* Deploy novo commit:

```bash
sudo ostree admin deploy raglinux/latest
```

* Reverter:

```bash
sudo ostree admin undeploy --rollback
```

* Instalar apps sem tocar root:

  * Flatpak
  * Podman / Distrobox (containers)
  * Diretórios em `/home/<usuário>`

---

## 🌐 Mirror brasileiro

* Pacman configurado para:

```
Server = https://br.mirrors.cicku.me/archlinux/$repo/os/$arch
```

---

## 💡 Dicas finais

* Sempre use `raglinux.sh` para instalação e upgrades.
* Para instalar apps de forma segura, utilize **containers ou flatpak**.
* Lembre-se que `/` é imutável; alterações diretas fora do OSTree não persistem.

---

### Autor

Gabriel Aguiar Rocha – [GitHub](https://github.com/gabrielrocha)

---

```

---

Se você quiser, posso criar uma **versão ainda mais detalhada**, incluindo **passo-a-passo de todo o build**, **comandos do Podman e OSTree**, e **prints de erros comuns e suas soluções**, para servir como documentação completa para qualquer usuário do RAGLinux.  

Quer que eu faça essa versão expandida?
```
