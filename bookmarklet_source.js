(function(){
	if (window.jQuery === undefined) {		
		var script = document.createElement("script");
		script.src = "//code.jquery.com/jquery-1.10.1.min.js";
		script.onload = script.onreadystatechange = function(){
			if (!done && (!this.readyState || this.readyState == "loaded" || this.readyState == "complete")) {
				load_bookmarklet();
			}
		};
		document.getElementsByTagName("head")[0].appendChild(script);
	} else {
		load_bookmarklet();
	}	
	var initBookmarklet = function() {
		$.getScript("//minimicro.herokuapp.com/bookmarklet/app.js");
	}
})();