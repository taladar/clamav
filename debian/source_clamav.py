'''apport package hook for clamav

(c) 2012 Canonical Ltd.
Author: Marc Deslauriers <marc.deslauriers@canonical.com>
'''

from apport.hookutils import *

def add_info(report):
    # Get configuration files
    attach_conffiles(report, 'clamav-freshclam')
    attach_conffiles(report, 'clamav-daemon')
    attach_file_if_exists(report, '/etc/clamav/clamd.conf')
    attach_file_if_exists(report, '/etc/clamav/freshclam.conf')

    # Get apparmor logs
    attach_mac_events(report, ['/usr/bin/freshclam', '/usr/sbin/clamd'])
