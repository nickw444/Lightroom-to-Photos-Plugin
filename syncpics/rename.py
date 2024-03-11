import os, re

for item in os.listdir('.'):
    name, ext = os.path.splitext(item)
    if m := re.match(r'nk-pb - (\d+)', name):
        new = f'nk-pb - {m.group(1).rjust(3, "0")}{ext}'
        print(item, new)
        os.rename(item, new)
