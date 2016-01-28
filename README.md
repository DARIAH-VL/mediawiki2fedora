# mediawiki2fedora

Tool to map archive mediawiki pages in a Fedora Commons (version 3) repository.

### Usage
```
$ carton exec perl bin/mediawiki2fedora.pl [--force]
```
Parameters:
  - force: force update of object/datastream if it exists already

### Configuration
See catmandu.yml:
```
#fedora login details
fedora:
  #baseurl
  - "http://localhost:8080/fedora"
  #username
  - "fedoraAdmin"
  #password
  - "fedoraAdmin"

#login details for mediawiki rest api
mediawiki:
  url: "https://localhost:8080/w/api.php"
  lgname: admin
  lgpassword: admin

namespace_page: mediawiki
namespace_revision: mediawikirevision
ownerId: admin

# which importer to use (see key 'importer')
mediawiki_importer: mediawiki
#available importers
importer:
  mediawiki:
    package: "Catmandu::Importer::MediaWiki"
    options:
      fix: "mediawiki"
      url: "https://localhost:8080/w/api.php"
      lgname: admin
      lgpassword: admin
      args:
        prop: "revisions|imageinfo|links"
        rvprop: "ids|flags|timestamp|user|comment|size|content|sha1|tags|userid|parsedcomment"
        rvlimit: "max"
        gaplimit: 100
        gapfilterredir: "nonredirects"
        iiprop: "url|mime|canonicaltitle|size|dimensions|sha1|user|timestamp"
        iilimit: 10

```
