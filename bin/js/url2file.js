var system = require('system');
var args = system.args;

if(args.length < 3){
  console.log("usage: phantomjs "+args[0]+" <url> <file> [<format>]");
  phantom.exit(1);
}

var page = require('webpage').create();
var url = args[1];
var output = args[2];
var format = null;

if ( args.length < 4 ) {

  var pos = output.lastIndexOf('.');
  if ( pos >= 0 ) {

    format = output.substring(pos+1).toLowerCase();

  }

} else {

  format = args[3];

}

if ( format == null ) {
  console.log("unable to determine format");
  phantom.exit(1);
}

page.viewportSize = { width: 1680, height: 1050 };
page.open(url, function(stat) {
  //webkit uses media="print" to render pdf, and media="screen" for images
  page.evaluate(function () {
    var links = document.getElementsByTagName('link');
    for (var i = 0, len = links.length; i < len; ++i) {
      var link = links[i];
      if (link.rel == 'stylesheet') {
        if (link.media == 'screen') { link.media = ''; }
        if (link.media == 'print') { link.media = 'ignore'; }
      }
    }
  });
  page.render(output,{ quality: '100', format: format });
  phantom.exit();
});
