// Original code: 
// https://github.com/ariya/phantomjs/blob/master/examples/waitfor.js
// https://github.com/ariya/phantomjs/blob/master/examples/rasterize.js

/**
 * Wait until the test condition is true or a timeout occurs. Useful for waiting
 * on a server response or for a ui change (fadeIn, etc.) to occur.
 *
 * @param testFx javascript condition that evaluates to a boolean,
 * it can be passed in as a string (e.g.: "1 == 1" or "$('#bar').is(':visible')" or
 * as a callback function.
 * @param onReady what to do when testFx condition is fulfilled,
 * it can be passed in as a string (e.g.: "1 == 1" or "$('#bar').is(':visible')" or
 * as a callback function.
 * @param timeOutMillis the max amount of time to wait. If not specified, 3 sec is used.
 */

function waitFor(testFx, onReady, timeOutMillis) {
	//< Default Max Timout is 20s
	var maxtimeOutMillis = timeOutMillis ? timeOutMillis : 20000,
		start = new Date().getTime(),
		condition = false,
		interval = setInterval(function() {
			if ((new Date().getTime() - start < maxtimeOutMillis) && !condition) {
				// If not time-out yet and condition not yet fulfilled
				condition = (typeof(testFx) === "string" ? eval(testFx) : testFx());
			} else {
				if (!condition) {
					// If condition still not fulfilled (timeout but condition is 'false')
					console.log("'waitFor()' timeout");
					phantom.exit(1);
				} else {
					// Condition fulfilled (timeout and/or condition is 'true')
					console.log("'waitFor()' finished in " + (new Date().getTime() - start) + "ms.");
					// onReady: Do what it's supposed to do once the condition is fulfilled
					typeof(onReady) === "string" ? eval(onReady) : onReady();
					clearInterval(interval); //< Stop this interval
				}
			}
		}, 250); //< repeat check every 250ms
};

var page = require('webpage').create(),
	system = require('system'),
	fs = require('fs'),
	address, output, page;

if (system.args.length != 3) {
	console.log('Usage: phantomjs load_ajax.js URL output_filename');
	console.log('  Example: phantomjs load_ajax.js' +
		' http://www.androiddrawer.com/search-results/?q=evernote evernote-results.html');
	phantom.exit(1);
} else {
	address = system.args[1];
	outputFile = system.args[2];


	// Open the address of the given webpage and, onPageLoad, do...
	page.open(address, function(status) {

		// Check for page load success
		if (status !== "success") {
			console.log("Unable to access network");
		} else {
			// Wait for 'gsc-resultsbox-visible' to be visible
			waitFor(function() {
				// Check in the page if a specific element is now visible
				return page.evaluate(function() {
					return $(".gsc-table-result").is(":visible");
					//CHANGE THE LINE OF CODE ABOVE TO ACCESS PAGES
				});
			}, function() {
				console.log("The search results list should be visible now." +
					" Downloading the web page for you..");
				try {
					fs.write(outputFile, page.content, 'w')
				} catch (e) {
					console.log("Error while writing to the file. " + e.message)
				}
				console.log("The web page has been downloaded at: " + outputFile)
				phantom.exit();
			});
		}
	});

}