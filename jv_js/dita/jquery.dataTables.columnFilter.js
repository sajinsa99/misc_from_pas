(function (factory) {
    "use strict";

    if (typeof define === 'function' && define.amd) {
        // AMD
        define(['jquery'], function ($) {
            return factory($, window, document);
        });
    }
    else if (typeof exports === 'object') {
        // CommonJS
        module.exports = function (root, $) {
            if (!root) {
                // CommonJS environments without a window global must pass a
                // root. This will give an error otherwise
                root = window;
            }

            if (!$) {
                $ = typeof window !== 'undefined' ? // jQuery's factory checks for a global window
                    require('jquery') :
                    require('jquery')(root);
            }

            return factory($, root, root.document);
        };
    }
    else {
        // Browser
        factory(jQuery, window, document);
    }
}
    (function ($, window, document, undefined) {
        'use strict';

        var DataTable = $.fn.dataTable;

        var _filters = DataTable.ext.columnFilters;

        var getUrlParameters = function getUrlParameter(tableId) {
            if (tableId === undefined) {
                return [];
            }
            var sPageURL = window.location.search.substring(1),
                sURLVariables = sPageURL.split('&'),
                sParameter,
                i,
                presets = [];
            for (i = 0; i < sURLVariables.length; i++) {
                sParameter = decodeURIComponent(sURLVariables[i]).split('=');
                var name = sParameter[0];
                var value = sParameter[1];
                if (name.indexOf(tableId) > -1) {
                    presets.push([sParameter[0].substring(name.lastIndexOf(tableId) + tableId.length + 1), sParameter[1]]);
                }
            }
            return presets;
        };

        var ColumnFilters = function (table, columnParams) {



            var dt = new DataTable.Api(table);


            this.c = $.extend(true, [], ColumnFilters.defaults, columnParams);

            var dtSettings = dt.settings()[0];
            if (dtSettings._columnFilters) {
                throw "ColumnFilters already initialized on table " + dtSettings.nTable.id;
            }
            dtSettings._columnFilters = this;

            this.s = {
                dt: dt,
                columnFilters: [],
                filterPresets: getUrlParameters(dt.settings()[0].oInit.sapTableId),
                displayedColumnFilters: $()
            }

            this._constructor();
        };

        //BASE FILTER CLASS
        var Filter = function (idx, context, id) {
            this.idx = idx;
            this.context = context;
            this.element = $();
            this.state = [];
            this.number = 0;
            this.id = id;
        };
        Filter.prototype.addElement = function () { };
        Filter.prototype.addListeners = function () { };
        Filter.prototype.setState = function (state) {
        };
        Filter.prototype.search = function () { };
        Filter.prototype.getState = function () { return this.state };
        Filter.prototype.checkDefaults = function () {
            if (this.id) {
                var presets = this.context.s.filterPresets;
                for (var i = 0; i < presets.length; i++) {
                    if (presets[i][0] === this.id) {
                        this.addDefaults(presets[i][1]);
                    } 
                }
                this.context.s.dt.draw();
            }
        };
        Filter.prototype.saveState = function (state) {
            if (this.context.s.saveState && this.state !== state) {
                this.state = state;
                this.element.trigger('triggerSave');
            }
        }
        Filter.prototype.addDefaults = function () { };

        //TEXT FILTER
        var TextFilter = function (idx, bRegex, context, id) {
            Filter.call(this, idx, context, id);
            this.bRegex = bRegex;
            this.number = 1;
        }
        TextFilter.prototype = Object.create(Filter.prototype);
        TextFilter.prototype.constructor = TextFilter;
        TextFilter.prototype.addElement = function () {
            var filter = $('<th><span class="filter_column filter_text"><input class="display" type="text" value="" placeholder="' + this.context.s.dt.i18n('sSearchColumnPlaceholder') + '" /><span class="tablesearch"/></span></th>');
            $.data(filter, 'type', 'text');
            $.data(filter, 'bRegex', this.bRegex);
            this.element = filter;
        };
        TextFilter.prototype.addListeners = function () {
            var filter = this.element;
            var column = this.context.s.dt.column(this.idx);
            var that = this;

            filter.find('input').on('keyup change', function () {
                if (column.search() !== this.value) {
                    column
                        .search(this.value, $.data(filter, 'bRegex'))
                        .draw();
                    that.saveState(this.value);
                }
            });

            // $(document).on('init.dt.dth', function () {
            //     that.checkDefaults();
            // });
        }
        TextFilter.prototype.addDefaults = function (value) {
            var filter = this.element;
            var column = this.context.s.dt.column(this.idx);
            filter.find('input').val(value);
            column.search(value, $.data(filter, 'bRegex'));
            column.draw();
        }
        TextFilter.prototype.setState = function (value) {
            this.addDefaults(value);
            this.saveState(value);
        }

        //NUMBER FILTER
        var NumberFilter = function (idx, bRegex, context, id) {
            TextFilter.call(this, idx, bRegex, context, id);
            this.number = 2;
        }
        NumberFilter.prototype = Object.create(TextFilter.prototype);
        NumberFilter.prototype.constructor = NumberFilter;
        NumberFilter.prototype.addElement = function () {
            var filter = $('<th><span class="filter_column filter_text number_filter"><input class="display" type="number" value="" placeholder="Filter" /><span class="tablesearch"/></span></th>');
            $.data(filter, 'type', 'text');
            this.element = filter;
        }

        //MULTI SELECT
        var SelectFilter = function (idx, context, id) {
            Filter.call(this, idx, context, id);
            this.number = 3;
        }
        SelectFilter.prototype = Object.create(Filter.prototype);
        SelectFilter.prototype.constructor = SelectFilter;
        SelectFilter.prototype.normalizeSearchQueries = function (str) {
            try {
                $(str);
                return str;
            } catch (e) {
                return str
                    .replace(/&(?:[a-z\d]+|#\d+|#x[a-f\d]+);/ig, '')
                    .replace(/([\!\#\$\%\\&;(\)\*\+,\.\/:=<>\?@\[\]\^\`\{\|\}\~'"])/g, "");
            }
        }
        SelectFilter.prototype.addElement = function () {
            var column = this.context.s.dt.column(this.idx);
            var data = $(column.nodes().to$());
            var that = this;
            var idx = this.idx;
            var localization = {
                blankLabel: this.context.s.dt.i18n('sEmptyCells'),
                filter: this.context.s.dt.i18n('sFilter') === "" ? "Filter" : this.context.s.dt.i18n('sFilter'),
                selectAll: this.context.s.dt.i18n('sSelectAll') === "" ? "Select All" : this.context.s.dt.i18n('sSelectAll'),
                removeFilter: this.context.s.dt.i18n('sRemoveFilter') === "" ? "Remove Filter" : this.context.s.dt.i18n('sRemoveFilter')
            };
            var listAsHtml = [];
            var listLabels = [];
            var createMultiSelectFromListItems = function (data) {
                $.each(data, function (index, value) {
                    if ($(value).find('li.sli').length === 0) {
                        var item = $("<item>" + value.innerHTML + "</item>");
                        $(item).html($.trim($(item).html()));
                        if (listAsHtml.indexOf($(item).html()) === -1) {
                            listAsHtml.push($(item).html());
                            listLabels.push($(item).text().trim());
                        }
                    } else {
                        $(value).find('li.sli').each(function () {
                            $(this).html($.trim($(this).html()));
                            if (listAsHtml.indexOf($(this).html()) === -1) {
                                listAsHtml.push($(this).html());
                                listLabels.push($(this).text().trim());
                            }
                        });
                    }

                });
            }

            createMultiSelectFromListItems(data);

            var list = buildList(listAsHtml, listLabels, localization);
            var filter = $("<div><label><a href='#'><span class='hida'>" + localization.filter + "</span></a></label></div>");
            $(filter).append("<div class='multiSelect'></div>");
            $(filter.children('.multiSelect')).html(list);

            var th = $('<th class="dropdown"> </th>');


            th.append(filter);

            $.fn.dataTable.ext.search.push(
                function (settings, rowDataTextArray, rowNumber, rowDataObjectArray) {
                    if (settings.nTable.id !== that.context.id) {
                        return true;
                    }
                    var searchTerms = [];
                    var checked = $(th).find('.multiSelect input:checked');
                    if (checked.length === 0) {
                        return true;
                    }
                    $.each(checked, function (idx, itm) {
                        searchTerms.push(that.normalizeSearchQueries($(itm).attr('data-label')))
                    });

                    var cellTerms = [];
                    var containsList = false;
                    var value = that.context.s.dt.cell(rowNumber, idx).nodes().to$();
                    $(value).find('li.sli').each(function () {
                        containsList = true;
                        var str = that.normalizeSearchQueries($(this).text().trim());
                        cellTerms.push(str);
                        $(this).removeClass('dt_highlight');
                    });
                    if (!containsList) {
                        var text = $(value).text().trim();
                        cellTerms.push(that.normalizeSearchQueries(text));
                    }

                    var intersect = searchTerms.filter(function (n) {
                        return cellTerms.indexOf(n) !== -1;
                    });

                    that.saveState(searchTerms);

                    if (intersect.length > 0) {
                        return true;
                    } else {
                        return false;
                    }
                }
            );

            $.data(th, 'type', 'select');
            this.element = th;

            function escapeHtml(text) {
                return text.replace(/[\"&<>]/g, function (a) {
                    return { '"': '&quot;', '&': '&amp;', '<': '&lt;', '>': '&gt;' }[a];
                });
            }

            function createListItem(value, dataLabel, label) {
                var listItem = $("<li class='sli'></li>");
                listItem.append($("<input type='checkbox' value='" + escapeHtml(value) +
                    "' data-label='" + dataLabel + "'/>"));
                listItem.append(label);
                return listItem;
            }

            function getRemoveFilter(label) {
                var listItem = $("<li class='sli list-function remove-filter'></li>");
                var filter = $("<a href='#'></a>");
                filter.text(label);
                listItem.append(filter);
                return listItem;
            }

            function getSelectAllFilter(label) {
                var listItem = $("<li class='sli list-function select-all'></li>");
                var filter = $("<a href='#'></a>");
                filter.text(label);
                listItem.append(filter);
                return listItem;
            }

            function buildList(listAsHtml, listLabels, localization) {
                var list = [];
                var hasBlank = false;
                var blankHtml = '';
                for (var i = 0; i < listAsHtml.length; i++) {
                    var listItem = createListItem(listAsHtml[i], listLabels[i], listLabels[i]);
                    if (listLabels[i] === "") {
                        blankHtml = listAsHtml[i];
                        hasBlank = true;
                    } else {
                        list.push(listItem);
                    }
                }
                list.sort(function (a, b) {
                    return $(a).text().toUpperCase().localeCompare($(b).text().toUpperCase());
                });
                var sortedList = $("<ul></ul>");
                $.each(list, function (idx, itm) { sortedList.append(itm) });
                if (hasBlank) {
                    sortedList.prepend(createListItem(blankHtml, '', localization.blankLabel));
                }
                sortedList.prepend(getRemoveFilter(localization.removeFilter));
                sortedList.prepend(getSelectAllFilter(localization.selectAll));
                return sortedList;
            }





        };
        SelectFilter.prototype.addListeners = function () {
            var th = this.element;
            var context = this.context;
            var that = this;
            th.find('.multiSelect').hide();
            th.find('label').on('click', function () {
                $(this).next('.multiSelect').toggle();
                return false;
            });
            th.find('.select-all').children().on('click', function() {
                $(this).parent().siblings().find('input:checkbox:not(checked)').prop('checked', true);
                context.s.dt.draw();
                return false;
            });
            th.find('.remove-filter').children().on('click', function() {
                $(this).parent().siblings().find('input:checkbox:checked').prop('checked', false);
                context.s.dt.draw();
                return false;
            });
            th.find('.multiSelect').on('change', function () {
                context.s.dt.draw();
            });
        };
        SelectFilter.prototype.addDefaults = function (value) {
            var that = this;
            this.element.find('input').each(function (input) {
                if ($(this).attr('data-label') === value || that.normalizeSearchQueries($(this).attr('data-label')) === value) {
                    $(this).prop('checked', true);
                }
            });
        }
        SelectFilter.prototype.setState = function (values) {
            for (var i = 0; i < values.length; i++) {
                this.addDefaults(values[i]);
            }
        }

        //NUMBER RANGE
        var NumberRangeFilter = function (idx, context, id) {
            Filter.call(this, idx, context, id);
            this.number = 4;
        }
        NumberRangeFilter.prototype = Object.create(Filter.prototype);
        NumberRangeFilter.prototype.constructor = NumberRangeFilter;
        NumberRangeFilter.prototype.addElement = function () {
            var filter = $('<th class="number-range"></th>');
            var from = $('<input class="dt-from" type="number" placeholder="' + this.context.s.dt.i18n('sFrom') + '" min="0">');
            var to = $('<input class="dt-to" type="number" placeholder="' + this.context.s.dt.i18n('sTo') + '" min="0">');
            var that = this
            var idx = this.idx;
            filter.append(from);
            filter.append(to);
            $.data(filter, 'type', 'number-range');
            $.fn.dataTable.ext.search.push(
                function (settings, rowDataTextArray, rowNumber, rowDataObjectArray) {

                    if (settings.nTable.id !== that.context.id) {
                        return true;
                    }

                    var min = from.val();
                    var max = to.val();

                    that.saveState([min, max]);
                    var cellValue = rowDataTextArray[idx] === "-" ? "" : rowDataTextArray[idx] * 1;
                    if (min === "" && max === "") {
                        return true;
                    }

                    else if (min === "" && cellValue <= max) {
                        return true;
                    }

                    else if (min <= cellValue && "" === max) {
                        return true;
                    }

                    else if (min <= cellValue && cellValue <= max) {
                        return true;
                    }

                    return false;
                }
            );
            this.element = filter;
        }
        NumberRangeFilter.prototype.addListeners = function () {
            var filter = this.element;
            var column = this.context.s.dt.column(this.idx);
            filter.find('input').on('keyup change', function () {
                column.draw();
            });
        }
        NumberRangeFilter.prototype.setState = function (values) {
            var filter = this.element;
            filter.find('input.dt-from').val(values[0]);
            filter.find('input.dt-to').val(values[1]);
        }

        //CELL RANGE
        var CellRangeFilter = function (idx, context, id) {
            Filter.call(this, idx, context, id);
            this.number = 5;
        }
        CellRangeFilter.prototype = Object.create(Filter.prototype);
        CellRangeFilter.prototype.constructor = CellRangeFilter;
        CellRangeFilter.prototype.addElement = function () {
            var filter = $('<th class="filter_column filter_number cell-range"></th>');
            var input = $('<input type="number" placeholder="' + this.context.s.dt.i18n('sSearchRange') + '" min="0"></input>');
            filter.append(input);
            $.data(filter, 'type', 'cell-range');
            var that = this;
            var idx = this.idx;
            $.fn.dataTable.ext.search.push(
                function (settings, rowDataTextArray, rowNumber, rowDataObjectArray) {
                    if (settings.nTable.id !== that.context.id) {
                        return true;
                    }
                    var query = input.val();

                    that.saveState(query);

                    if (query === '') {
                        return true;
                    }
                    query = query * 1;
                    var cellValue = rowDataTextArray[idx];
                    var regexSingleNumber = new RegExp('^[0-9]+$');
                    var regexNumberRange = new RegExp('^[0-9]+-[0-9]+');
                    if (regexSingleNumber.test(cellValue)) {
                        if (query === cellValue) {
                            return true;
                        }
                    } else if (regexNumberRange.test(cellValue)) {
                        var numbers = cellValue.split('-');
                        var min = numbers[0];
                        var max = numbers[1];
                        if (min <= query && query <= max) {
                            return true
                        }
                    }
                    return false;
                }
            );
            this.element = filter;
        }
        CellRangeFilter.prototype.addListeners = function () {
            var filter = this.element;
            var column = this.context.s.dt.column(this.idx);
            filter.find('input').on('keyup change', function () {
                column.draw();
            });
        }

        CellRangeFilter.prototype.addDefaults = function (value) {
            var filter = this.element;
            filter.find('input').val(value);
            this.context.s.dt.column(this.idx).draw();
        }

        CellRangeFilter.prototype.setState = function (value) {
            this.addDefaults(value);
            this.saveState(value);
        }

        var NullFilter = function (idx, context) {
            Filter.call(this, idx, context);
            this.number = 6;
        }
        NullFilter.prototype = Object.create(Filter.prototype);
        NullFilter.prototype.constructor = NullFilter;
        NullFilter.prototype.addElement = function () {
            var filter = $("<th></th>");
            $.data(filter, 'type', 'none');
            this.element = filter;
        }



        $.extend(ColumnFilters.prototype, {
            /**
             * Add a new button
             * @param {object} config ColumnFilter configuration object
             * @param {int|string} [idx] Button index for where to insert the button
             * @return {ColumnFilters} Self for chaining
             */
            add: function (config, idx) {
                var filterDefaults = {
                    type: 'text',
                    bRegex: 'false',
                    id: ''
                }

                var columnFilterParams = $.extend(true, {}, filterDefaults, config);
                var type = columnFilterParams.type;
                var bRegex = columnFilterParams.bRegex;
                var id = columnFilterParams.id;
                var that = this;

                if (type === "text") {
                    var filter = new TextFilter(idx, bRegex, that, id);
                } else if (type === "number") {
                    var filter = new NumberFilter(idx, bRegex, that, id);
                } else if (type === "select") {
                    var filter = new SelectFilter(idx, that, id);
                } else if (type === "number-range") {
                    var filter = new NumberRangeFilter(idx, that, id);
                } else if (type === "cell-range") {
                    var filter = new CellRangeFilter(idx, that, id);
                } else {
                    var filter = new NullFilter(idx, that, id);
                }
                filter.addElement();
                this.s.columnFilters.push(filter);

                return this;
            },


            /* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
             * Constructor
             */

            /**
             * ColumnFilter constructor 
             * Create column filters where necessary
             * 
             * @private 
             */
            _constructor: function () {
                var that = this;
                var dt = this.s.dt;
                var id = dt.settings()[0].sInstance;
                var filterRowId = id + "_filterrow";
                this.id = id;
                var dtObj = $('#' + id);
                var columnFilters = this.s.columnFilters;
                if (dt.settings()[0].oInit.searchHighlight) {
                    var dtEvent = 'highlight-init';
                } else {
                    var dtEvent = 'init.dt.dth';
                }

                this.s.displayedColumnFilters = $("<tr></tr>")
                    .attr("id", filterRowId);
                $('#' + id).find('thead').first().append(this.s.displayedColumnFilters);
                for (var i = 0; i < this.c.length; i++) {
                    this.add(this.c[i], i);
                }
                this._update();

                var initialStateSave = dt.settings()[0].oInit.bStateSave;
                this.s.saveState = initialStateSave;
                var x = 'DataTables_' + id;
                for (var i = 0; i < columnFilters.length; i++) {
                    x += columnFilters[i].number;
                }
                var dtLocalStorageId = x;

                if (initialStateSave) {
                    dtObj.on(dtEvent, function () {
                        var unparsed = localStorage.getItem(dtLocalStorageId);
                        if (unparsed !== null) {
                            var state = JSON.parse(unparsed);
                            for (var i = 0; i < that.c.length; i++) {
                                columnFilters[i].setState(state.columnValues[i]);
                            }
                        }
                    });


                    dtObj.on('triggerSave', function () {

                        var unparsed = localStorage.getItem(dtLocalStorageId);
                        if (unparsed !== null) {
                            var data = JSON.parse(unparsed);
                        } else {
                            var data = dt.state();
                        }
                        if (data.columnValues === undefined) {
                            data.columnValues = new Array(that.c.length);
                        }
                        for (var i = 0; i < that.c.length; i++) {
                            data.columnValues[i] = columnFilters[i].getState();
                        }
                        localStorage.setItem(dtLocalStorageId, JSON.stringify(data));

                    });
                } else {
                    dtObj.on(dtEvent, function () {
                        for (var i = 0; i < that.c.length; i++) {
                            columnFilters[i].checkDefaults();
                        }
                        //Check global table filter (where no column ID provided)
                        for (var i = 0; i < that.s.filterPresets.length; i ++) {
                            var preset = that.s.filterPresets[i];
                            if (preset[0] === "") {
                                var query = preset[1];
                                dt.search(query).draw();
                            }
                        }
                    });
                }

                $(document).on('column-visibility.dt', '#' + id, function () {
                    that._update();
                });


                $(document).bind('click', function (e) {
                    var $clicked = $(e.target);
                    if (!$clicked.parents().hasClass("dropdown")) {
                        $(".dropdown .multiSelect").hide();
                    }
                });

            },

            /**
             * Update shown filters based on which columns are visible 
             */
            _update: function () {
                var displayed = this.s.displayedColumnFilters;
                displayed.empty();
                var visibleColumns = [];
                this.s.dt.columns().every(function () {
                    if (this.visible()) {
                        visibleColumns.push(this.index());
                    }
                });
                var filters = this.s.columnFilters;
                for (var i = 0; i < filters.length; i++) {
                    var filter = filters[i];
                    if (visibleColumns.indexOf(filter.idx) > -1) {
                        $(displayed).append(filter.element);
                        filter.addListeners();
                    }
                }

            }
        });

        /**
         * Defaults
         * @type {Object}
         * @static
         */
        ColumnFilters.defaults = {

        };

        jQuery.fn.dataTableExt.oSort["alpha-numeric-asc"] = function (x, y) {
            var aToken = new RegExp("^([a-zA-Z]*)(.*)");
            var firstToken = aToken.exec(x);
            var secondToken = aToken.exec(y);
            if (firstToken[1] > secondToken[1]) {
                return 1;
            }
            if (firstToken[1] < secondToken[1]) {
                return -1;
            }
            firstToken[2] = parseInt(firstToken[2]);
            secondToken[2] = parseInt(secondToken[2]);
            if (firstToken[2] < secondToken[2]) {
                return -1;
            }
            if (firstToken[2] > secondToken[2]) {
                return 1;
            }
            else {
                return 0;
            }
        };
        jQuery.fn.dataTableExt.oSort["alpha-numeric-desc"] = function (x, y) {
            var aToken = new RegExp("^([a-zA-Z]*)(.*)");
            var firstToken = aToken.exec(x);
            var secondToken = aToken.exec(y);
            if (firstToken[1] > secondToken[1]) {
                return -1;
            }
            if (firstToken[1] < secondToken[1]) {
                return 1;
            }
            firstToken[2] = parseInt(firstToken[2]);
            secondToken[2] = parseInt(secondToken[2]);
            if (firstToken[2] < secondToken[2]) {
                return 1;
            }
            if (firstToken[2] > secondToken[2]) {
                return -1;
            }
            else {
                return 0;
            }
        };

        /* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
         * DataTables interfaces
         */

        // Attach for constructor access    
        $.fn.dataTable.ColumnFilters = ColumnFilters;
        $.fn.DataTable.ColumnFilters = ColumnFilters;

        // DataTables creation - check if the ColumnFilters option has been defined on the
        // table and if so, initialise
        $(document).on('init.dt plugin-init.dt', function (e, settings) {
  
            var opts = settings.oInit.columnFilters || DataTable.defaults.columnFilters;

            if (opts && !settings._columnFilters) {
                new ColumnFilters(settings, opts);
            }

        });

    }));
