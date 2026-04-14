with open('all_certs.pem', 'r') as f:
    content = f.read()

certs = content.split('-----BEGIN CERTIFICATE-----')

for i, cert in enumerate(certs):
    if cert.strip():
        filename = f'cert-{i:02d}.cer'
        with open(filename, 'w') as out:
            out.write('-----BEGIN CERTIFICATE-----' + cert)
        print(f'Created {filename}')
