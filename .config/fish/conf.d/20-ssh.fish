if test "$_os" = darwin
    set -l sock "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"
    if test -S "$sock"
        set -x SSH_AUTH_SOCK "$sock"
    else
        echo "Warning: Secretive SSH agent socket not found" >&2
    end
end
