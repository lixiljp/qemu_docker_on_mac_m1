#!/bin/sh

# The cores used by qemu instance
QEMU_CPUS=4
# The memory used by qemu instance
QEMU_MEMORY="4G"
# The folder path used to store qemu image and startup script
QEMU_IMAGE_DIR="${HOME}/.qemu/ubuntu"
# The maximum size of qemu image, qemu will allocate it incremental
QEMU_IMAGE_SIZE="100G"
# The folder share with qemu instance (notice it's writable)
QEMU_SHARE_FOLDER="${HOME}"
# The application show up in Applications
MAC_APPLICATION_NAME="Ubuntu"
# The path of iso file for installation
ISO_FILE_PATH="$(ls ~/Downloads/ubuntu-*-server-arm64.iso | head -n 1)"
# The ssh port used on the host, make sure no other application use it
HOST_SSH_PORT=2200
# The username use to login, make sure it matched the user you created
SSH_USERNAME="ubuntu"
# The port forwading parameters pass to ssh, depend on your application inside docker
# for example, -L 127.0.0.1:8000:127.0.0.1:80 will forward guest 80 to host 8000
# if you want to change it later, you can modify $QEMU_IMAGE_DIR/startup.sh
PORT_FORWARD_PARAMS="-L 127.0.0.1:3000:127.0.0.1:3000 -L 127.0.0.1:5000:127.0.0.1:5000 -L 127.0.0.1:1080:127.0.0.1:1080"

create () {
    echo "create qemu image..."
    mkdir -p "${QEMU_IMAGE_DIR}"
    qemu-img create -f qcow2 "${QEMU_IMAGE_DIR}/image.qcow2" "${QEMU_IMAGE_SIZE}"
    dd if=/dev/zero of="${QEMU_IMAGE_DIR}/ovmf_vars.fd" bs=1m count=64

    echo "create startup script..."
    cat << EOF > "${QEMU_IMAGE_DIR}/startup.sh"
#!/bin/sh
echo "start qemu instance..."
if [[ "\$(pgrep -f 'file=${QEMU_IMAGE_DIR}/image.qcow2')" = "" ]]; then
  qemu-system-aarch64 \\
    -machine virt,accel=hvf,highmem=off \\
    -cpu cortex-a72 -smp ${QEMU_CPUS} -m ${QEMU_MEMORY} \\
    -device qemu-xhci,id=usb-bus \\
    -device usb-tablet,bus=usb-bus.0 \\
    -device usb-mouse,bus=usb-bus.0 \\
    -device usb-kbd,bus=usb-bus.0 \\
    -device virtio-gpu-pci \\
    -display default,show-cursor=on \\
    -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:${HOST_SSH_PORT}-0.0.0.0:22,smb=${QEMU_SHARE_FOLDER}" \\
    -drive "format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,if=pflash,readonly=on" \\
    -drive "format=raw,file=${QEMU_IMAGE_DIR}/ovmf_vars.fd,if=pflash" \\
    -drive "format=qcow2,file=${QEMU_IMAGE_DIR}/image.qcow2" &
    echo "instance started"
else
    echo "instance already started"
fi
pkill sh \$0
echo "setup port forwading..."
while true; do
  # you can change the port forwading parameters here
  ssh ${PORT_FORWARD_PARAMS} -N -p ${HOST_SSH_PORT} ${SSH_USERNAME}@127.0.0.1
  sleep 5
done
EOF

    echo "start instance with iso image..."
    echo "NOTICE: you need to install the system yourself and enable openssh server"
    echo "NOTICE: you must create a user named ${SSH_USERNAME} for ssh login"
    qemu-system-aarch64 \
      -machine virt,accel=hvf,highmem=off \
      -cpu cortex-a72 -smp ${QEMU_CPUS} -m ${QEMU_MEMORY} \
      -device qemu-xhci,id=usb-bus \
      -device usb-tablet,bus=usb-bus.0 \
      -device usb-mouse,bus=usb-bus.0 \
      -device usb-kbd,bus=usb-bus.0 \
      -device virtio-gpu-pci \
      -display default,show-cursor=on \
      -nic user,model=virtio \
      -drive "format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,if=pflash,readonly=on" \
      -drive "format=raw,file=${QEMU_IMAGE_DIR}/ovmf_vars.fd,if=pflash" \
      -drive "format=qcow2,file=${QEMU_IMAGE_DIR}/image.qcow2" \
      -cdrom "${ISO_FILE_PATH}"

    echo "setup completed, please setup ssh login before execute configure command"
    echo "for example:"
    echo
    echo "# start qemu instance"
    echo "# notice it will blocking for port forwarding, you should open a new tab to enter the following commands"
    echo "sh ${QEMU_IMAGE_DIR}/startup.sh"
    echo
    echo "# generate ssh key, if you already have one please skip"
    echo "ssh-keygen"
    echo
    echo "# copy ssh public key to qemu instance, you will need to enter the password"
    echo "ssh-copy-id -p ${HOST_SSH_PORT} ${SSH_USERNAME}@127.0.0.1"
    echo
    echo "# remove the password"
    echo "ssh -p ${HOST_SSH_PORT} ${SSH_USERNAME}@127.0.0.1 -t 'sudo passwd -d ${SSH_USERNAME}'"
}

configure () {
    set -e
    echo "start configure"

    echo "test ssh connection..."
    ssh -p "${HOST_SSH_PORT}" "${SSH_USERNAME}@127.0.0.1" -t "uname -a"

    echo "upgrade system..."
    ssh -p "${HOST_SSH_PORT}" "${SSH_USERNAME}@127.0.0.1" -t "sudo apt update && sudo apt upgrade -y"

    echo "replace grub config to reduce wating time..."
    ssh -p "${HOST_SSH_PORT}" "${SSH_USERNAME}@127.0.0.1" -t "
      sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=3/g' /etc/default/grub && sudo update-grub"

    echo "install samba and enable folder sharing..."
    ssh -p "${HOST_SSH_PORT}" "${SSH_USERNAME}@127.0.0.1" -t "
      sudo apt install -y cifs-utils smbclient &&
      sudo sed -i 's|//10.0.2.4/qemu .*||g' /etc/fstab &&
      echo '//10.0.2.4/qemu '${QEMU_SHARE_FOLDER}' cifs user=nobody,password=nobody,uid=1000,gid=1000 0 0' | sudo tee -a /etc/fstab &&
      cat /etc/fstab &&
      sudo mkdir -p '${QEMU_SHARE_FOLDER}' &&
      sudo mount '${QEMU_SHARE_FOLDER}' || true"

    echo "install docker..."
    ssh -p "${HOST_SSH_PORT}" "${SSH_USERNAME}@127.0.0.1" -t "
      sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release &&
      sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg &&
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&
      echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null &&
      sudo apt update &&
      sudo apt install -y docker-ce net-tools qemu binfmt-support qemu-user-static &&
      sudo systemctl enable docker &&
      sudo systemctl start docker &&
      sudo groupadd docker || true &&
      sudo usermod -aG docker \$USER &&
      sudo curl -L \"https://github.com/docker/compose/releases/download/v2.0.1/docker-compose-linux-\$(uname -m)\" -o /usr/local/bin/docker-compose &&
      sudo chmod +x /usr/local/bin/docker-compose"

    echo "test docker commands..."
    ssh -p "${HOST_SSH_PORT}" "${SSH_USERNAME}@127.0.0.1" -t "docker --version && docker-compose --version && docker ps"

    echo "create docker commands on host..."
    cat << EOF | sudo tee /usr/local/bin/docker > /dev/null
#!/usr/bin/env python3
import sys
import os
import pipes

def main():
    workdir = os.getcwd()
    filename = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    cmd = f"ssh -p '${HOST_SSH_PORT}' '${SSH_USERNAME}@127.0.0.1' -qt \"cd {pipes.quote(workdir)} && {pipes.quote(filename)} {' '.join(map(pipes.quote, args))}\""
    # print(cmd)
    os.system(cmd)

if __name__ == "__main__":
    main()
EOF
    sudo cp /usr/local/bin/docker /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker /usr/local/bin/docker-compose

    echo "test docker commands on host..."
    docker --version && docker-compose --version && docker ps

    echo "create application..."
    mkdir -p "${MAC_APPLICATION_NAME}.app/Contents/MacOS"
    echo "#!/bin/zsh\nosascript -e 'tell app \"Terminal\"\n  do script \"nohup sh '${QEMU_IMAGE_DIR}/startup.sh' > /dev/null 2> /dev/null &!; exit;\"\nend tell'" > "${MAC_APPLICATION_NAME}.app/Contents/MacOS/${MAC_APPLICATION_NAME}"
    chmod +x "${MAC_APPLICATION_NAME}.app/Contents/MacOS/${MAC_APPLICATION_NAME}"
    sudo rm -rf "/Applications/${MAC_APPLICATION_NAME}.app"
    sudo mv "${MAC_APPLICATION_NAME}.app" /Applications

    echo "configure completed, you can launch ${MAC_APPLICATION_NAME} from Applications to start the qemu instance next time"
    echo "you can also add ${MAC_APPLICATION_NAME} to Login Items so it can be automatically started after login"
}

if [[ "$1" = "create" ]]; then
    create
elif [[ "$1" = "configure" ]]; then
    configure
else
    echo "$0 create|configure"
fi
