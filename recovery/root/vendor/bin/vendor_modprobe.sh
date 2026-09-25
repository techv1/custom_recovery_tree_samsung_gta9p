#!/system/bin/sh
# ==============================================================================
# Dependency-Aware Touchscreen & Core Driver Loader for SM-X216B (gta9p)
# ==============================================================================

MOD_DIR="/vendor/lib/modules"
if [ ! -d "$MOD_DIR" ]; then
    MOD_DIR="/vendor/lib/modules/5.4-gki"
fi

if [ ! -d "$MOD_DIR" ]; then
    echo "vendor_modprobe: No module directory found" > /dev/kmsg
    exit 1
fi

load_module_recursive() {
    target="$1"
    
    # Check if already loaded in /proc/modules
    name="${target%.ko}"
    if grep -q "^${name} " /proc/modules 2>/dev/null; then
        return 0
    fi
    
    # Parse dependencies from modules.dep if present
    if [ -f "$MOD_DIR/modules.dep" ]; then
        dep_line=$(grep "^${target}:" "$MOD_DIR/modules.dep" | head -n 1)
        if [ -n "$dep_line" ]; then
            deps=$(echo "$dep_line" | cut -d: -f2)
            for d in $deps; do
                if [ -n "$d" ] && [ -f "$MOD_DIR/$d" ]; then
                    load_module_recursive "$d"
                fi
            done
        fi
    fi
    
    # Now load target module
    if [ -f "$MOD_DIR/$target" ]; then
        if [ -x /system/bin/modprobe ]; then
            /system/bin/modprobe -b -d "$MOD_DIR" "$name" 2>/dev/null
        fi
        if ! grep -q "^${name} " /proc/modules 2>/dev/null; then
            /system/bin/insmod "$MOD_DIR/$target" 2>/dev/null
        fi
        if grep -q "^${name} " /proc/modules 2>/dev/null; then
            echo "vendor_modprobe: Loaded $target" > /dev/kmsg
        else
            echo "vendor_modprobe: Failed to load $target" > /dev/kmsg
        fi
    fi
}

echo "vendor_modprobe: Starting dependency-aware Himax touch driver initialization..." > /dev/kmsg

# Load primary Himax touch driver and all its hardware dependencies recursively
load_module_recursive "himax_mmi.ko"

# If Himax successfully initialized or panel recognized, we're done
if grep -q "^himax_mmi " /proc/modules 2>/dev/null; then
    echo "vendor_modprobe: Himax touch driver initialized successfully" > /dev/kmsg
    exit 0
fi

# Fallback: if Himax did not bind (hardware variant fallback), check modules.load
if [ -f "$MOD_DIR/modules.load" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        mod=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$mod" ]; then
            load_module_recursive "$mod"
        fi
    done < "$MOD_DIR/modules.load"
fi

exit 0
