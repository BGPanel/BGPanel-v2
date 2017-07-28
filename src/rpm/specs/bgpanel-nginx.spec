Name:           bgpanel-nginx
Version:        0.1.0
Release:        1
Summary:        Bright Game Panel
Group:          System Environment/Base
License:        MIT
URL:            http://bgpanel.net
Vendor:         bgpanel.net
Source0:        %{name}-%{version}.tar.gz
Source1:        nginx.conf
Source2:        bgpanel.init
Requires:       redhat-release >= 5
Provides:       bgpanel-nginx
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

%description
This package contains nginx webserver for Bright Game Panel web interface.

%prep
%setup -q -n %{name}-%{version}

%build
./configure --prefix=/usr/local/bgpanel/nginx --with-http_ssl_module
make

%install
make install DESTDIR=%{buildroot} INSTALLDIRS=vendor
%{__install} -p -D -m 0755 %{SOURCE1} %{buildroot}/usr/local/bgpanel/nginx/conf/nginx.conf
%{__install} -p -D -m 0755 %{SOURCE2} %{buildroot}%{_initrddir}/bgpanel
%{__install} -p -D -m 0755  %{buildroot}/usr/local/bgpanel/nginx/sbin/nginx %{buildroot}/usr/local/bgpanel/nginx/sbin/bgpanel-nginx
%clean
rm -rf %{buildroot}

%post
/sbin/chkconfig --add bgpanel

%preun
if [ $1 = 0 ]; then
    /sbin/service bgpanel stop >/dev/null 2>&1
    /sbin/chkconfig --del bgpanel
fi

%postun
if [ $1 -ge 1 ]; then
    if [ -e "/var/run/bgpanel-nginx.pid" ]; then
        /sbin/service bgpanel restart > /dev/null 2>&1 || :
    fi
fi

%files
%defattr(-,root,root)
%attr(755,root,root) /usr/local/bgpanel/nginx
%{_initrddir}/bgpanel
%config(noreplace) /usr/local/bgpanel/nginx/conf/nginx.conf


%changelog
* Fri Jul 28 2017 BGPanel Team <packages@bgpanel.net> - 0.1.0
- Initial release of bgpanel-nginx, using nginx 1.13.3