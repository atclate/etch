Name: etch-client
Summary: Etch client
Version: %VER%
Release: 1
Group: Applications/System
License: MIT
buildarch: noarch
Requires: ruby, facter, crontabs, cpio
BuildRoot: %{_builddir}/%{name}-buildroot
%description
Etch client

%files
%defattr(-,root,root)
/usr/sbin/etch
/usr/sbin/etch_to_trunk
/usr/lib/ruby/site_ruby/1.8/etch.rb
/usr/lib/ruby/site_ruby/1.8/etch/client.rb
/usr/lib/ruby/site_ruby/1.8/silently.rb
/usr/lib/ruby/site_ruby/1.8/versiontype.rb
/usr/share/man/man8/etch.8
/etc/etch.conf
/etc/etch
/usr/sbin/etch_cron_wrapper
/etc/cron.d/etch

