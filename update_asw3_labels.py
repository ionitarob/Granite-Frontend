import os
import sys
import django

# Add backend to path
sys.path.append(r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from apps.sentinel.models import Switch, SwitchPort

def update_labels():
    try:
        sw = Switch.objects.get(name='a-sw3')
        print(f"Updating labels for Switch: {sw.name} (ID: {sw.switch_id})")

        # Mapping: {table_number: (start_port, end_port)}
        mapping = {
            17: (38, 43),
            18: (1, 6),
            19: (7, 12),
            20: (45, 47),
            21: (13, 18),
            22: (19, 24),
            23: (25, 35),
        }

        # Compile all mapped port numbers
        mapped_ports = []
        for start, end in mapping.values():
            mapped_ports.extend(range(start, end + 1))

        # Update labeled ports and ensure they are enabled
        updated_count = 0
        for table_num, (start_port, end_port) in mapping.items():
            for port_num in range(start_port, end_port + 1):
                label = f"A-{table_num}-P{port_num:02d}"
                port, created = SwitchPort.objects.get_or_create(
                    switch=sw,
                    port_number=port_num,
                    defaults={'label': label, 'enabled': True}
                )
                if not created:
                    port.label = label
                    port.enabled = True
                    port.save()
                
                print(f"  Port {port_num} -> {label} (ENABLED)")
                updated_count += 1
        
        # Disable all ports NOT in mapped_ports
        all_ports = SwitchPort.objects.filter(switch=sw)
        disabled_count = 0
        for port in all_ports:
            if port.port_number not in mapped_ports:
                if port.enabled:
                    port.enabled = False
                    port.save()
                    print(f"  Port {port.port_number} -> DISABLED")
                    disabled_count += 1
        
        print(f"SUCCESS: Updated {updated_count} ports. Disabled {disabled_count} unused ports.")

    except Switch.DoesNotExist:
        print("ERROR: Switch 'a-sw3' not found in database.")
    except Exception as e:
        print(f"ERROR: {e}")

if __name__ == '__main__':
    update_labels()
