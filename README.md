-----

# RAGostree-utility


**RAGLinux** é um sistema operacional baseado em **Arch Linux** com uma abordagem moderna e robusta: um sistema de arquivos raiz **imutável**, gerenciado de forma atômica pelo **OSTree** e construído com a flexibilidade do **Podman**.

O objetivo deste projeto é fornecer a estabilidade de um sistema imutável, onde as atualizações são seguras e reversíveis, combinada com a vasta gama de pacotes e a filosofia "faça você mesmo" do Arch Linux.

-----

## 🌟 Principais Características

  * **Sistema Imutável**: O diretório raiz (`/`) é montado como somente leitura, prevenindo modificações acidentais e garantindo que cada "versão" do sistema seja consistente e testada.
  * **Atualizações Atômicas**: As atualizações são aplicadas em uma nova "árvore" do sistema. A mudança para a nova versão ocorre em uma única operação (geralmente na reinicialização), eliminando o risco de um sistema quebrar no meio de uma atualização.
  * **Rollbacks Simples**: Se uma atualização causar problemas, reverter para a versão anterior funcional é um comando simples e instantâneo.
  * **Construção via Containers**: A imagem base do sistema é construída dentro de um container Podman, garantindo um ambiente de build limpo, reprodutível e isolado.
  * **Separação Clara**: O sistema operacional é estritamente separado dos dados e configurações do usuário, que residem em subvolumes Btrfs separados (`/home`, `/var`).

-----

## 🛠️ Tecnologias Utilizadas

  * **Base System**: [Arch Linux](https://archlinux.org/)
  * **Gerenciamento Atômico**: [OSTree](https://ostreedev.github.io/ostree/)
  * **Sistema de Arquivos**: [Btrfs](https://btrfs.wiki.kernel.org/)
  * **Construção (Build)**: [Podman](https://podman.io/)
  * **Bootloader**: [GRUB](https://www.gnu.org/software/grub/)

-----

## 🚀 Estrutura do Projeto

```
raglinux/
├── raglinux.sh             # Script principal de instalação e gerenciamento
├── Containerfile.base      # Define a imagem base do sistema (pacotes e configs)
├── post-install.sh         # (Opcional) Script para configurações pós-instalação
├── archlinux/              # Configurações específicas do Arch
├── cachyos/                # (Opcional) Configurações para builds alternativas
└── Containerfile.host.example # Exemplo para customizações do host
```

-----

## ⚙️ Uso e Gerenciamento

O script `raglinux.sh` é a principal ferramenta para interagir com o sistema em nível de build e deploy.

### Instalação Inicial

Para criar o primeiro deployment do sistema em um dispositivo de bloco (ex: `/dev/sda`).

```bash
# Exemplo de uso
./raglinux.sh install --dev /dev/sda --keymap br-abnt2 --time America/Sao_Paulo
```

### Atualizando o Sistema (Upgrade)

Isso irá construir uma nova imagem, criar um novo commit no OSTree e prepará-lo para ser o próximo boot.

```bash
# Cria um novo commit OSTree com as últimas atualizações
./raglinux.sh upgrade
```

Após o upgrade, reinicie o sistema para aplicar a nova versão.

### Revertendo uma Atualização (Rollback)

Caso a última atualização apresente algum problema, você pode facilmente reverter.

```bash
# Reverte para o deployment anterior (marcado como 0)
./raglinux.sh revert
```

### Opções do Script `raglinux.sh`

| Opção | Argumento Longo | Descrição | Padrão |
| :--- | :--- | :--- |:--- |
| `-b` | `--base-os` | Nome do sistema operacional para o repositório OSTree. | `raglinux` |
| `-c` | `--cmdline` | Argumentos extras para a linha de comando do Kernel. | |
| `-d` | `--dev` | Dispositivo de bloco (SCSI/NVMe) para a instalação. | |
| `-f` | `--file` | Caminho para o(s) `Containerfile`(s) a serem usados no build. | |
| `-k` | `--keymap` | Layout de teclado para o console (TTY). | |
| `-t` | `--time` | Fuso horário (Timezone) no formato `Região/Cidade`. | |
| `-m` | `--merge` | Mantém o diretório `/etc` durante um upgrade. | |
| `-n` | `--no-cache` | Ignora o cache do Pacman e do Podman durante o build. | |
| `-q` | `--quiet` | Reduz a quantidade de logs exibidos na saída. | |

-----

## 📦 Gerenciamento de Aplicações

Em um sistema imutável, o gerenciamento de pacotes tradicional (`pacman -S ...`) não é usado diretamente no sistema host. Em vez disso, a instalação de aplicações de usuário é feita de forma isolada:

  * **Flatpak**: O método recomendado para aplicações gráficas. Elas rodam em seu próprio sandbox e não alteram o sistema base.
  * **Podman / Distrobox**: Ideal para ferramentas de linha de comando e ambientes de desenvolvimento. Crie containers com as distribuições e pacotes que precisar, sem "sujar" o sistema host.
  * **Binários em `/home`**: Para aplicações simples que não requerem dependências complexas, você pode executá-las a partir do seu diretório pessoal.

-----

## 🗂️ Estrutura do Sistema de Arquivos (Pós-instalação)

O RAGLinux utiliza subvolumes Btrfs para separar os dados do sistema.

  * `/` (raiz): **Imutável**. Gerenciado pelo OSTree.
  * `/home`: Subvolume `@home`. **Mutável**. Armazena os arquivos e configurações dos usuários.
  * `/var`: Subvolume `@var`. **Mutável**. Contém dados variáveis como logs, caches de aplicações, etc.
  * `/ostree`: Subvolume `@ostree`. Contém os deployments (versões) do sistema operacional.
  * `/boot/efi`: Partição EFI para o bootloader.

-----

## 🧠 Desafios Resolvidos Durante o Desenvolvimento

1.  **Espaço Insuficiente no LiveCD (`airootfs`)**

      * **Problema**: O ambiente de instalação do Arch tem um `tmpfs` limitado, que estourava durante o build do container.
      * **Solução**: Direcionar o diretório temporário e a raiz do Podman para o disco de destino (`/mnt`), que possui espaço de sobra.
        ```bash
        export TMPDIR=/mnt/podman/tmp
        # Configurar /mnt/podman como storage root do Podman
        ```

2.  **Volume do Podman Não Encontrado**

      * **Problema**: O Podman não conseguia montar o cache do Pacman pois o diretório de destino não existia no host antes do build.
      * **Solução**: Criar manualmente a estrutura de diretórios do cache antes de invocar o comando `podman build`.
        ```bash
        mkdir -p /mnt/podman/var/cache/pacman
        ```

3.  **GRUB Não se Instalava Corretamente no Chroot**

      * **Problema**: O comando `grub-mkconfig` falhava por não encontrar os dispositivos e informações do sistema quando executado de um chroot simples.
      * **Solução**: Fazer o bind mount dos pseudo-sistemas de arquivos (`/dev`, `/proc`, `/sys`) do host para dentro do ambiente chroot antes de executar o comando.
        ```bash
        for i in /dev /proc /sys; do mount -o bind $i ${DEPLOY_PATH}${i}; done
        chroot ${DEPLOY_PATH} grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg
        ```

-----

## 🌐 Configurações Padrão

  * **Espelho Brasileiro do Pacman**: Para garantir downloads mais rápidos, o `pacman.conf` é configurado por padrão para utilizar o espelho `br.mirrors.cicku.me`.
  * **Pacotes Base**: A imagem (`Containerfile.base`) inclui um sistema funcional com Plasma Desktop (KDE), ferramentas de containerização (Podman, Distrobox), Pipewire para áudio e outros utilitários essenciais.

-----

### Autor

Gabriel Aguiar Rocha – [GitHub](https://github.com/gabrielrocha)
