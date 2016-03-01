Name: mediawiki2fedora
Summary: Tool to archive mediawiki pages in a Fedora Commons (version 3) repository
License: perl
Version: 0.01
Release: X
BuildArch: noarch
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires: perl-5.20.2
Requires: make
Requires: gcc
Requires: pcre
Requires: pcre-devel
Requires: expat-devel
Requires: zlib-devel
Requires: perl-Module-Build
Requires: perl-YAML
Requires: perl-CPAN
Requires: perl-App-cpanminus
Requires: fontconfig
Requires: fontconfig-devel
Requires: pandoc
Requires: wget
Source: %{name}.tar.gz

%description
Tool to archive mediawiki pages in a Fedora Commons (version 3) repository

%prep
#rpm package 'redhat-rpm-config'
%setup -q -n %{name}
%filter_provides_in -P .
%filter_requires_in -P .
%filter_setup

%build
echo "build complete"

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/%{name}
mkdir -p %{buildroot}/var/log/%{name}
cp -r $RPM_BUILD_DIR/%{name}/* %{buildroot}/opt/%{name}/
echo "install complete"

%clean
rm -rf %{buildroot}

%files
%defattr(-,fedora,fedora,-)
%attr(644,root,root) /opt/%{name}/cron.d/%{name}.cron
/opt/%{name}/
/var/log/%{name}

%doc

#http://www.rpm.org/max-rpm/s1-rpm-inside-scripts.html
%post
( cd /opt/%name && ./postinstall.sh ) || exit 1

%changelog
