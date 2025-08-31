## OSTree no Arch Linux usando Podman

Um grande agradecimento a [M1cha](https://github.com/M1cha/) por tornar isso possível ([M1cha/archlinux-ostree](https://github.com/M1cha/archlinux-ostree)).

### Visão geral

Este é um script auxiliar que ajuda a criar sua própria configuração, demonstrando como:

1. Construir uma imagem OSTree imutável usando o **rootfs** a partir de um Containerfile do Podman.
2. Particionar e preparar discos UEFI/GPT para um sistema host mínimo com OSTree.
3. Gerar um repositório OSTree em um sistema de arquivos vazio.
4. Integrar o OSTree com o carregador de boot GRUB2.
5. Atualizar um repositório OSTree existente com uma nova imagem rootfs.

### Estrutura do disco

```console
/
├── boot
│   └── efi
└── ostree
    ├── deploy
    │   └── archlinux
    └── repo
        ├── config
        ├── extensions
        ├── objects
        ├── refs
        ├── state
        └── tmp
```

### Persistência

Tudo é apagado entre os deploys **exceto**:

* Partições em `/dev` onde o OSTree não está armazenado.
* `/etc`, mas somente se a opção `--merge` for especificada.
* `/home`, que é um symlink para `/var/home` (veja abaixo).
* Os dados de `/var` vêm de `/ostree/deploy/archlinux/var` para evitar duplicação.

Notas:

* `/var/cache/podman` só é populado após o primeiro deploy (para evitar inclusão de dados antigos da máquina de build), acelerando builds consecutivos.
* `/var/lib/containers` segue a mesma lógica, mas para camadas e imagens do Podman. Imagens base são atualizadas automaticamente durante o comando `upgrade`.

### Stack de tecnologias

* OSTree
* Podman com CRUN e Native-Overlayfs
* GRUB2
* XFS *(não obrigatório)*

### Motivação

Minha visão é construir um sistema base seguro e mínimo, resiliente contra falhas e que forneça automação de configuração para reduzir a carga de tarefas manuais. Isso pode ser alcançado com:

* Git.
* Arquivos de sistema somente leitura.
* Pontos de restauração.
* Deploy, instalação e configuração automáticos.
* Uso apenas dos componentes necessários (kernel/firmware/driver, microcode e GCC no sistema base).
* Todo o resto rodando em namespaces temporários, como o Podman.

### Objetivos

* Deploys reproduzíveis.
* Rollbacks versionados.
* Sistema de arquivos imutável.
* Ferramentas independentes da distribuição.
* Gerenciamento de configuração.
* Criação de rootfs via containers.
* Cada deploy realiza um "reset de fábrica" da configuração do sistema *(a menos que sobrescrito)*.

### Projetos semelhantes

* **[Elemental Toolkit](https://github.com/rancher/elemental-toolkit)**
* **[KairOS](https://github.com/kairos-io/kairos)**
* **[BootC](https://github.com/containers/bootc)**
* [NixOS](https://nixos.org)
* [ABRoot](https://github.com/Vanilla-OS/ABRoot)
* [Transactional Update + BTRFS snapshots](https://microos.opensuse.org)
* [AshOS](https://github.com/ashos/ashos)
* [LinuxKit](https://github.com/linuxkit/linuxkit)

---

## Uso

1. **Inicialize em qualquer sistema Arch Linux:**

   Por exemplo, usando uma imagem ISO live CD/USB: [Arch Linux Downloads](https://archlinux.org/download).

2. **Clone este repositório:**

   ```console
   $ sudo pacman -Sy git
   $ git clone https://github.com/GrabbenD/ostree-utility.git && cd ostree-utility
   ```

3. **Encontre o `ID-LINK` do dispositivo onde a imagem OSTree será instalada:**

   ```console
   $ lsblk -o NAME,TYPE,FSTYPE,MODEL,ID-LINK,SIZE,MOUNTPOINTS,LABEL
   ```

4. **Realize a instalação (takeover):**

   ⚠️ **AVISO** ⚠️

   `ostree.sh` é destrutivo e **não faz perguntas** ao particionar o disco especificado. **Tenha cuidado!**

   ```console
   $ chmod +x ostree.sh
   $ sudo ./ostree.sh install --dev scsi-360022480c22be84f8a61b39bbaed612f
   ```

   ⚙️ Atualize a ordem de boot no BIOS para iniciar a instalação.

   💡 Login padrão: `root` / `ostree`

   💡 Use Containerfile(s) diferentes com a opção `--file FILE1:TAG1,FILE2:TAG2`

5. **Atualizar uma instalação existente:**

   Dentro de um sistema OSTree:

   ```console
   $ sudo ./ostree.sh upgrade
   ```

   💡 Use a opção `--merge` para preservar o conteúdo de `/etc`.

6. **Reverter para um commit anterior:**

   Para desfazer o último deploy *(0)*, inicie na configuração anterior *(1)* e execute:

   ```console
   $ sudo ./ostree.sh revert
   ```

---

## Dicas

### Somente leitura

Esse atributo pode ser removido temporariamente com OverlayFS, permitindo modificar caminhos somente leitura sem salvar as alterações:

```console
$ ostree admin unlock
```

### Cache desatualizado do repositório

> `error: failed retrieving file '{name}.pkg.tar.zst' from {source} : The requested URL returned error: 404`

Seu cache persistente está fora de sincronia com o upstream, resolva com:

```console
$ ./ostree.sh upgrade --no-podman-cache
```

---

Quer que eu também adapte essa tradução para o estilo de **um guia/tutorial passo a passo em português**, bem fluido e didático, como se fosse de um blog tipo Diolinux?
