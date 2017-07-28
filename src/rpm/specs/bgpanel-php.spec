Name:           bgpanel-php
Version:        0.1.0
Release:        1
Summary:        Bright Game Panel PHP
Group:          System Environment/Base
License:        MIT
URL:            http://bgpanel.net
Vendor:         bgpanel.net
Source0:        %{name}-%{version}.tar.gz
Source1:        php.ini
Source2:        php-fpm.conf
Requires:       redhat-release >= 5
Provides:       bgpanel-php
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

%description
This package contains php-cgi for Bright Game Panel web interface.

%prep
%setup -q -n %{name}-%{version}

%build
./configure --prefix=/usr/local/bgpanel/php --with-zlib --enable-fpm --with-fpm-user=admin --with-fpm-group=admin --with-mysql --with-mysqli --with-curl --enable-mbstring

make

%install
make install INSTALL_ROOT=%{buildroot} INSTALLDIRS=vendor
install -p -D -m 0755 %{SOURCE1} %{buildroot}/usr/local/bgpanel/php/lib/
%{__install} -p -D -m 0755 %{SOURCE2} %{buildroot}/usr/local/bgpanel/php/etc/
%{__install} -p -D -m 0755  %{buildroot}/usr/local/bgpanel/php/sbin/php-fpm %{buildroot}/usr/local/vesta/php/sbin/vesta-php


rm -rf $RPM_BUILD_ROOT/.channels
rm -rf $RPM_BUILD_ROOT/.depdb
rm -rf $RPM_BUILD_ROOT/.depdblock
rm -rf $RPM_BUILD_ROOT/.filemap
rm -rf $RPM_BUILD_ROOT/.lock

%clean
rm -rf %{buildroot}

%postun
if [ $1 -ge 1 ]; then
    if [ -e "/var/run/bgpanel-php.pid" ]; then
        /sbin/service bgpanel restart > /dev/null 2>&1 || :
    fi
fi

%files
%defattr(-,root,root)
%attr(755,root,root) /usr/local/bgpanel/php

%changelog
* Fri Jul 28 2017 BGPanel Team <packages@bgpanel.net> - 0.1.0
- Initial package build and release
