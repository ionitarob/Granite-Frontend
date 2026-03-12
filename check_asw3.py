import os
import sys
import django

# Add backend to path
sys.path.append(r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from apps.sentinel.models import Switch, SwitchPort

def check_switch():
    try:
        sw = Switch.objects.get(name='a-sw3')
        print(f"FOUND SWITCH: ID={sw.switch_id}, Name={sw.name}, IP={sw.ip}")
        ports = SwitchPort.objects.filter(switch=sw).order_by('port_number')
        print(f"EXISTING PORTS: {ports.count()}")
        for p in ports:
            print(f"  Port {p.port_number}: {p.label}")
    except Switch.DoesNotExist:
        print("SWITCH NOT FOUND: a-sw3")
    except Exception as e:
        print(f"ERROR: {e}")

if __name__ == '__main__':
    check_switch()
