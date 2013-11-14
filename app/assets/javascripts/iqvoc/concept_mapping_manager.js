/*jslint vars: true, white: true */
/*global jQuery, IQVOC */

IQVOC.conceptMappingManager = (function($) {

"use strict";

function ConceptMappingManager(selector) {
  this.root = selector.jquery ? selector : $(selector);
  this.conceptMappings = this.determineConceptMappings();

  this.list = $("<ul />").prependTo(this.root);
  this.render();

  this.root.on("concept-mapped", $.proxy(this, "onUpdate"));
}
ConceptMappingManager.prototype.render = function() {
  var self = this;

  var items = [];
  $.each(this.conceptMappings, function(label, category) {
    $.each(category.values, function(i, item) {
      var item = self.renderBubble(item, label);
      items.push(item);
    });
  });

  this.list.empty().append(items);
};
ConceptMappingManager.prototype.renderBubble = function(item, categoryLabel) {
  var category = $("<span />").text(categoryLabel);
  var source = $("<span />").text(item.source);
  return $("<li />").text(item.uri).append(category).prepend(source);
};

// [{ el: jQuery Element, values: ["http://uri.de"], label: "Foo" }]
ConceptMappingManager.prototype.determineConceptMappings = function() {
  var textAreas = this.root.find('textarea');

  var labels = {};
  this.root.find("label").each(function(i, node) {
    var el = $(node);
    labels[el.attr("for")] = el.text();
  });

  var urisByLabel = {};
  textAreas.each(function(i, node) {
    var el = $(node);
    var label = labels[el.attr("name")];
    var values = $.map($(node).val().split(","), function(item, i) {
      item = $.trim(item);
      return item ? { uri: item, source: "dummy" } : null;
    });

    // TODO: values zu Objekten machen, Source pro Value annotieren
    urisByLabel[label] = { el: el, values: values, source: "bar" };
  });

  return urisByLabel;
};
ConceptMappingManager.prototype.onUpdate = function(ev, data) {
  this.conceptMappings[data.matchType].values.
      push({ uri: data.uri, source: data.source });
  this.render();
};

return function(selector) {
  return new ConceptMappingManager(selector);
};

}(jQuery));
