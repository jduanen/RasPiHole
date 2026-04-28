# RasPiHole: RaspberryPi-based Pi-hole DNS Server with Unbound

WIP

# Hardware
  - using RasPi3B with 1GB DRAM
  - uSD
    * critical to have reliable and fast one
    * aim for 32-128GB capacity, Class 10/UHS-I minimum
      - avoid A2-rated cards on Pi 3B as they underperform due to limited controller support
    * SanDisk Extreme Pro is good choice (A1-rated, U3/V30 speed class)
      - best Pi 3B+ IOzone tests (similar to 3B), with ~20MB/s practical speeds
      - SanDisk excels here for OS logging/boot without corruption risks
    * Pi 3B's SD interface caps at ~20-25MB/s, so endurance (TBW rating)
      - random I/O matter more than peak speeds
    * official recommendations include: SanDisk Ultra and Samsung EVO Select for compatibility

  - PSU
    * critical to have a robust one
    * use official RasPi one

# Software

## Installation and Configuration
  1) install OS on uSD card
    * use the lastest raspi-imager
    * choose Raspberry Pi OS Lite (64-bit) Trixie
    * set hostname, enable ssh, disable wifi
  3) set static IP in router
  4) login and update system
    * `ssh jdn@pihole.local`
      - `sudo apt update && sudp apt upgrade -y`
  5) configure network
    * `sudo ex /etc/dhcpcd.conf`
      - add at the bottom
        * 'interface eth0'
        * 'static ip_address=192.168.1.2/24'
        * 'static routers=192.168.1.1'
        * 'static domain_name_servers=127.0.0.1'
    * `sudo reboot`
  6) install and configure Unbound
    * `sudo apt install unbound -y`
    * create the config file
      - `sudo ex /etc/unbound/unbound.conf.d/pi-hole.conf`
'''
server:
    verbosity: 0
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: no

    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    edns-buffer-size: 1472
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m

    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
'''
    * start and enable Unbound
      - `sudo systemctl enable unbound`
      - `sudo systemctl start unbound`   
    * check that it works
       - `dig pi-hole.net @127.0.0.1 -p 5335`
       - should get a valid response indicating that Unbound is running correctly
  7) install Pi-hole
    * `curl -sSL https://install.pi-hole.net | bash`
      - use interactive installer
        * upstream DNS: Custom -> '127.0.0.1#5335'
          - this points Pi-hole at the local Unbound instance instead of an external DNS provider
  8) verify the stack
    * query through Pi-hole → Unbound → root servers
      - `dig pi-hole.net @127.0.0.1`
    * check Pi-hole is blocking ads
      - `dig doubleclick.net @127.0.0.1`
        * should return: '0.0.0.0'

  9) point router at Pi-hole
    * in router's DHCP settings: set the DNS server to the Pi's static IP
      - this automatically pushes the Pi-hole DNS to all devices on the network
    * make the Pi-hole be the primary DNS server, and maybe fall back to Google's?

  10) using the Pi-hole web UI
    * to access the dashboard goto:
      - `http://192.168.166.?/admin (or `http://pihole.local/admin`)
      - use the password shown at the end of the installer
        * can reset password anytime with:
          - `pihole -a -p`

  11) add recommended blocklists
    * in Pi-hole admin UI under 'Adlists', add:
      * `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
        - should already be the default
      * `https://oisd.nl/`
        - this is comprehensive and well-maintained
