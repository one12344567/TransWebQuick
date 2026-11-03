#!/usr/bin/env python3
"""Stable local development identity in a project-only keychain; no system trust changes."""
import os, pathlib, secrets, subprocess, sys, shlex
ROOT=pathlib.Path(__file__).resolve().parent.parent
STORE=ROOT/'native/.signing'
STORE.mkdir(exist_ok=True,mode=0o700)
os.chmod(STORE,0o700)
os.umask(0o077)
KC=STORE/'development.keychain-db'
PW=STORE/'keychain-password'
IDENTITY='PressTrans Local Development'
def run(args, **kw):
    return subprocess.run(args,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kw).stdout
try:
    if not PW.exists(): PW.write_text(secrets.token_urlsafe(32))
    password=PW.read_text()
    if not (STORE/"identity-ready").exists():
        config=STORE/'certificate.cnf'
        config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=extensions\nprompt=no\n[dn]\nCN=PressTrans Local Development\n[extensions]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n')
        if not (STORE/'certificate.pem').exists(): run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','3650','-config',str(config),'-keyout',str(STORE/'key.pem'),'-out',str(STORE/'certificate.pem')])
        run(['openssl','pkcs12','-export','-inkey',str(STORE/'key.pem'),'-in',str(STORE/'certificate.pem'),'-out',str(STORE/'identity.p12'),'-name',IDENTITY,'-passout','file:'+str(PW),'-keypbe','PBE-SHA1-3DES','-certpbe','PBE-SHA1-3DES','-macalg','sha1'])
        original=shlex.split(run(['security','list-keychains','-d','user']).decode())
        try:
            if not KC.exists(): run(['security','create-keychain','-p',password,str(KC)])
            run(['security','unlock-keychain','-p',password,str(KC)])
            run(['security','import',str(STORE/'identity.p12'),'-k',str(KC),'-P',password,'-T','/usr/bin/codesign'])
            run(['security','set-key-partition-list','-S','apple-tool:,apple:','-s','-k',password,str(KC)])
        finally:
            run(['security','list-keychains','-d','user','-s',*original])
        (STORE/'identity-ready').write_text('local code-signing identity initialized\n')
        (STORE/'key.pem').unlink()
        (STORE/'identity.p12').unlink()
    run(['security','unlock-keychain','-p',password,str(KC)])
    run(['codesign','--force','--timestamp=none','--sign',IDENTITY,'--keychain',str(KC),sys.argv[1]])
    run(['codesign','--verify','--strict',sys.argv[1]])
    print('Signed with persistent project-local development identity (not Developer ID notarization).')
except subprocess.CalledProcessError as error:
    # Never print argv: security commands include a generated local keychain password.
    print(error.stderr.decode(errors='replace'),file=sys.stderr)
    raise SystemExit('Local development signing failed; no ad-hoc fallback used.')
