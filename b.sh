tar --exclude='*/Cache' \
    --exclude='*/CacheStorage' \
    --exclude='*/CacheData' \
    --exclude='*/ScriptCache' \
    --exclude='*/node_modules' \
    --exclude='*/OptGuideOnDeviceModel' \
    --exclude='*/GPUCache' \
    --exclude='*/Code Cache' \
    --exclude='*/DawnCache' \
    --exclude='*/Session Storage' \
    --exclude='*/Service Worker/CacheStorage' \
    -czvf dev-backup.tar.gz \
    ~/.ssh ~/.gnupg ~/.config ~/.local/share/gnome-shell/extensions ~/.bashrc ~/.zshrc
