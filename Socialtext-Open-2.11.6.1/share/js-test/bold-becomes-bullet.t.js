var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(6);

if ( Wikiwyg.is_safari ) {
    t.skipAll("On Safari, we do not convert HTML to wikitext");
}
else {
    t.filters(filters);
    t.run_is('html', 'wikitext');
    t.run_roundtrip('wikitext');
}


t.run_is('html', 'wiitext');

/* Test
=== A bold becomes a bullet
--- html
<div class="wiki">
<p><span style="font-weight: bold;">
Bold me</span>: xxx</p>
<br></div>
--- wikitext
Bold me: xxx

=== A italic
--- html
<div class="wiki">
<p><span style="font-style: italic;">
Italic Me</span>: xxx</p>
<br></div>
--- wikitext
Italic Me: xxx

=== A line-through
--- html
<div class="wiki">
<p><span style="text-decoration: line-through;">
Thru Me</span>: xxx</p>
<br></div>
--- wikitext
Thru Me: xxx

*/

