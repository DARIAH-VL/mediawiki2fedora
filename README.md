mediawiki2fedora
================

Tool to archive mediawiki pages in a Fedora Commons (version 3) repository.

### Requirements
* perl >= 5.10.1
* fontconfig and fontconfig-devel
* pandoc
* wget

### Installation

Install all perl dependencies locally
```sh
$ cpanm Carton
$ cd mediawiki-fedora
$ carton install
```
### Configuration
Copy default catmandu.yml.default to catmandu.yml:
```
$ cp catmandu.yml.default catmandu.yml
```
Edit:
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

Insert Fedora models (execute only once!)

```
$ carton exec perl bin/insert_models.pl
```

Synchronize mediawiki and Fedora repository:
```
$ carton exec perl bin/mediawiki2fedora.pl [--force] [--delete]
```
Parameters:
  - **force**: force update of object/datastream if it exists already
  - **delete**: purge object in Fedora beforing trying to ingest. Good for starting all over.


### Background

This module archives a mediawiki website by deriving its history from the stored history
in mediawiki. It uses the mediawiki REST API to retrieve that history.

##### Page object

Every revision of a page in mediawiki is stored as a Fedora-Object, and conforms to the model **pageCModel**,
that has the following structure:
* datastream DC
* datastream RELS-EXT
* datastream RELS-INT
* datastream SRC
* datastream TXT
* datastream MARKDOWN
* datastream HTML
* datastream IMG
* datastream SCREENSHOT_PNG
* datastream SCREENSHOT_PDF

See file data/pageCModel.xml for more information about the model.

The Object label and Object title in Fedora is the title of the mediawiki page.
Users should query on those fedora fields to fetch all versions of a mediawiki page.

The datastream DC stores the following information:
* dc.title = title of the mediawiki paqe
* dc.identifier = mediawiki:\<pageid\>_\<revid\>
* dc.creator = user of the current revision
* dc.source = url of the mediawiki web page

The state can be "A" (archived) when it is the active (i.e. last) version,
or "I" (inactive) when this version is not active in mediawiki.

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
There are scripts in the wild, that try to convert from mediawiki to html, but they
cannot know which templates a specific mediawiki site uses to convert its pages, or
which special tags it uses.
Therefore we rely on the action [render](https://www.mediawiki.org/wiki/Manual:Parameters_to_index.php#Actions) that every page has.

The datastream *MARKDOWN* is derived from *HTML*, by transforming it to MARKDOWN.
This is indeed a double transformation, as HTML is already a transformation.
But as stated above, one cannot know how interpret the stored mediawiki text.

The datastream *IMG* is only used when the page is a description page of an image.
This contains the JPEG data of the image.

The datastreams *RELS-EXT* stores the following informat:
* Fedora model it belongs to
* Older Fedora object it replaces.

Example:
```
@prefix rel: <info:fedora/fedora-system:def/relations-external#> .
@prefix fedora-model: <info:fedora/fedora-system:def/model#> .
@prefix dc: <http://purl.org/dc/elements/1.1/> .
@prefix dcterms: = <http://purl.org/dc/terms/> .

"info:fedora/mediawiki:1_55"
    #fedora model it belongs to
    fedora-model:hasModel "info:fedora/mediawiki:pageCModel" ;
    #when this replaces an older version
    dcterms:replaces "info:fedora/mediawiki:1_54" .
```

The datastream RELS-INT stores the following information:
* datastream HTML is derivation of TXT
* datastream MARKDOWN is derivation of HTML

Example:
```
@prefix rel: <info:fedora/fedora-system:def/relations-external#> .
@prefix fedora-model: <info:fedora/fedora-system:def/model#> .
@prefix dc: <http://purl.org/dc/elements/1.1/> .
@prefix dcterms: = <http://purl.org/dc/terms/> .

"info:fedora/mediawiki:1_55/HTML" rel:isDerivationOf "info:fedora/mediawiki:1_55/TXT" .
"info:fedora/mediawiki:1_55/MARKDOWN" rel:isDerivationOf "info:fedora/mediawiki:1_55/HTML" .
```

The datastream SCREENSHOT_PDF is a screenshot of the revision webpage, and converted to PDF.

The datastream SCREENSHOT_PNG is a screenshot of the revision webpage, and converted to PNG.

## Remarks
* Every internal link (href and src) in the HTML page is broken. These links should be replaced by a link to a page object in Fedora. The HTML page does not specify which revision, as the mediawiki REST API does not specify this.
