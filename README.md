mediawiki2fedora
================

Tool to archive mediawiki pages in a Fedora Commons (version 3) repository.

### Installation

Install all perl dependencies locally
```sh
$ cpanm Carton
$ cd mediawiki-fedora
$ carton install
```
### Configuration
See catmandu.yml:
```yml
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

### Usage
```sh
$ carton exec perl bin/mediawiki2fedora.pl [--force]
```
Parameters:
  - **force**: force update of object/datastream if it exists already
 

### Background

This module archives a mediawiki website by deriving its history from the stored history
in mediawiki. It uses the mediawiki REST API to retrieve that history.

##### Page object

Every page in mediawiki is stored as a Fedora-Object, and conforms to the model **pageCModel**,
that has the following structure:
* datastream DC
* datastream RELS-EXT
* datastream RELS-INT

The Object label is the title of the mediawiki page.

The datastream DC stores this information:
* dc.title = title of the mediawiki paqe
* dc.identifier = mediawiki:<pageid>
* dc.creator = user of the first revision (see below)
* dc.source = url of the mediawiki web page

Since most information in mediawiki is stored in revisions, this object is only used as a starting point
(with minimal information) from which its history can be retrieved. Since revisions contain complex information (having tags, links, images, text ..), every revision is stored as separate object. The page ands its revisions are linked to each other using RDF.

The page object links to its revisions using the datastream RELS-EXT:
```
@prefix rel: <info:fedora/fedora-system:def/relations-external#> .
@prefix fedora-model: <info:fedora/fedora-system:def/model#> .
@prefix dc: <http://purl.org/dc/elements/1.1/> .
@prefix dcterms: = <http://purl.org/dc/terms/> .

"info:fedora/mediawiki:1"  
    rel:isCollection true ;
    fedora-model:hasModel "info:fedora/mediawiki:pageCModel" ;
    #reference to the latest revision
    dcterms:references "info:fedora/mediawikirevision:55" ;
    #links to revision (hasPart and hasVersion are synonyms in this case)
    dcterms:hasPart "info:fedora/mediawikirevision:55" ;
    dcterms:hasVersion "info:fedora/mediawikirevision:55" ;
    #older version
    dcterms:hasPart "info:fedora/mediawikirevision:54" ;
    dcterms:hasVersion "info:fedora/mediawikirevision:54" .
```

##### Revision object

A revision object in Fedora conforms to the model **revisionCModel**, and has the following structure:
* datastream DC
* datastream RELS-EXT
* datastream RELS-INT
* datastream SRC
* datastream TXT
* datastream HTML
* datastream IMG

The Object label is the title of the mediawiki page.

The state can be "A" (archived) when it is the active version,
or "I" (inactive) when this version is not active in mediawiki.

The datastream *DC* stores this information:
* dc.title = title of the mediawiki paqe
* dc.identifier = mediawiki:<revid>
* dc.creator = user of this revision
* dc.date = date this revision was created in mediawiki
* dc.source = url of the old version (**TODO**)

The datastream *SRC* is an JSON object, retrieved "as is" from the mediawiki REST-API,
as a means of backreference:

```
{
    parentid: 150,
    tags: [ ],
    parsedcomment: "",
    user: "Root",
    contentmodel: "wikitext",
    size: 1883,
    timestamp: "2015-11-26T16:51:01Z",
    userid: 1,
    sha1: "2168ff07d68fb8107b8fcbe0673e5febf7502dc7",
    *: "== Welcome! == The Manuscript Desk is an online environment in which manuscript pages can be uploaded, manuscript pages can be transcribed, and collations of transcriptions can be performed. The Manuscript Desk builds on, and extends different software components used in the Digital Humanities. The project is open-source, licenced under the [http://www.gnu.org/licenses/gpl-3.0.en.html GNU License]. Full installation instructions, and additional information on the technical structure of the software can be found on [https://github.com/akvankorlaar/manuscriptdesk GitHub]. Do you have suggestions or questions, or have you found a bug? You can always reach us at uamanuscriptdesk 'at' gmail 'dot' com. '''The Manuscript Desk is currently in its testing phase. Because of this, full access will only be given to persons that are invited'''. == New to this website? == Take a look at the [[Overview|overview]] of the features in the Manuscript Desk. == Credits == The Manuscript Desk has primarily been developed at the [https://www.uantwerpen.be/en/ University of Antwerp], but in close collaboration and with technical support from [https://www.ugent.be/en Ghent University]. The project is part of [http://be.dariah.eu/ DARIAH-Belgium]. The software components used include: * [https://www.mediawiki.org/wiki/MediaWiki Mediawiki software]. MediaWiki software powers [https://en.wikipedia.org/wiki/Main_Page Wikipedia], and many other wikis on the web. * Software created for the [http://blogs.ucl.ac.uk/transcribe-bentham/ Transcribe Bentham project]. The Transcribe Bentham project has created several open-source extensions for MediaWiki, which are used, and extended in the Manuscript Desk. * [http://collatex.net/ Collatex Software]. CollateX is used to collate different versions of texts. * [http://preloaders.net/ Preloaders] was used for the loader image.",
    comment: "",
    contentformat: "text/x-wiki",
    revid: "151"
}
```

The datastream *TXT* is derived from the datastream *SRC*, and stores the mediawiki text as is, 
without any transformation:

```
== Welcome! == The Manuscript Desk is an online environment in which manuscript pages can be uploaded, manuscript pages can be transcribed, and collations of transcriptions can be performed. The Manuscript Desk builds on, and extends different software components used in the Digital Humanities. The project is open-source, licenced under the [http://www.gnu.org/licenses/gpl-3.0.en.html GNU License]. Full installation instructions, and additional information on the technical structure of the software can be found on [https://github.com/akvankorlaar/manuscriptdesk GitHub]. Do you have suggestions or questions, or have you found a bug? You can always reach us at uamanuscriptdesk 'at' gmail 'dot' com. '''The Manuscript Desk is currently in its testing phase. Because of this, full access will only be given to persons that are invited'''. == New to this website? == Take a look at the [[Overview|overview]] of the features in the Manuscript Desk. == Credits == The Manuscript Desk has primarily been developed at the [https://www.uantwerpen.be/en/ University of Antwerp], but in close collaboration and with technical support from [https://www.ugent.be/en Ghent University]. The project is part of [http://be.dariah.eu/ DARIAH-Belgium]. The software components used include: * [https://www.mediawiki.org/wiki/MediaWiki Mediawiki software]. MediaWiki software powers [https://en.wikipedia.org/wiki/Main_Page Wikipedia], and many other wikis on the web. * Software created for the [http://blogs.ucl.ac.uk/transcribe-bentham/ Transcribe Bentham project]. The Transcribe Bentham project has created several open-source extensions for MediaWiki, which are used, and extended in the Manuscript Desk. * [http://collatex.net/ Collatex Software]. CollateX is used to collate different versions of texts. * [http://preloaders.net/ Preloaders] was used for the loader image.
```

The datastream *HTML* is derived from datastream *TXT*, by transforming it to HTML.

The datastream *IMG* is only used when the page is a description page of an image.
This contains the JPEG data of the image.

The datastreams *RELS-EXT* links to its parent using RDF-links:
```
@prefix rel: <info:fedora/fedora-system:def/relations-external#> .
@prefix fedora-model: <info:fedora/fedora-system:def/model#> .
@prefix dc: <http://purl.org/dc/elements/1.1/> .
@prefix dcterms: = <http://purl.org/dc/terms/> .

"info:fedora/mediawikirevision:55" 
    fedora-model:hasModel "info:fedora/mediawiki:revisionCModel" ;
    #link to parent object (using some synonyms)
    rel:isPartOf "info:fedora/mediawiki:1" ;
    rel:isMemberOf "info:fedora/mediawiki:1" ;
    dcterms:isPartOf "info:fedora/mediawiki:1" ;
    #when this replaces an older version
    dcterms:replaces "info:fedora/mediawikirevision:54" .
```

The datastream RELS-INT explains the link between datastream TXT and HTML:
```
@prefix rel: <info:fedora/fedora-system:def/relations-external#> .
@prefix fedora-model: <info:fedora/fedora-system:def/model#> .
@prefix dc: <http://purl.org/dc/elements/1.1/> .
@prefix dcterms: = <http://purl.org/dc/terms/> .

"info:fedora/mediawikirevision:55/HTML" rel:isDerivationOf "info:fedora/mediawikirevision:55/TXT"
```


## Remarks
* The HTML datastream should be the webpage itself, downloaded from its source, instead of trying to transform the TXT datastream, without any knowledge of how the TXT should be transformed. For every mediawiki website can configure this transformation differently. This HTML should be stored, together with the CSS, images and javascript files in a zip file
* Every revision should have a datastream SCREENSHOT that show the HTML page in JPEG.
* Every internal link (href and src) in the HTML page is broken. These links should be replaced by a link to a page object in Fedora. The HTML page does not specify which revision, as the mediawiki REST API does not specify this.
