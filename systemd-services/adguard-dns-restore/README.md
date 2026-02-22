After each reboot, DNS fallsback to `8.8.8.8` from `127.0.0.1` as the adguard image cannot be pulled to start the pod (`127.0.0.1` points to the adguard pod which is not yet running and therefore cannot access the internet).

Even once the adguard pod is running, DNS stays set to `8.8.8.8`. I want all traffic (both machine and cluster) to run through adguard for tracking purposes.

I have created a new service `adguard_dns_restore.service` that polls until the adguard pod is running. Once running, it restarts the `systemd-resolved` service. This means that I don't have to manually point the DNS back to adguard once it is running after every reboot.

Files to be symlinked:
```bash
/usr/local/bin/adguard_dns_restore.sh
/etc/systemd/system/adguard_dns_restore.service
```

