package sm_graphs;



##############################################################################
##############################################################################
##### declare uses
use Exporter;

use warnings;
use diagnostics;
use Carp qw(cluck confess); # to use instead of (warn die)



##############################################################################
##############################################################################
##### declare functions
sub sap_sm_print_div($$);
sub sap_sm_pie_chart($$$$$$);
sub sap_sm_drill_pie_chart($$$$$$);
sub sap_sm_line_chart($$$$$$$$);
sub sap_sm_line_chart_hms($$$$$$$$);
sub sap_sm_vertical_bar_graph($$$$$$);
sub sap_sm_horizonral_bar_graph($$$$$$$);


##############################################################################
##############################################################################
##### init vars
@ISA    = qw(Exporter);
@EXPORT = qw (
    &sap_sm_pie_chart
    &sap_sm_drill_pie_chart
    &sap_sm_line_chart
    &sap_sm_line_chart_hms
    &sap_sm_vertical_bar_graph
    &sap_sm_horizonral_bar_graph
);



##############################################################################
##############################################################################
#### my functions

sub sap_sm_pie_chart($$$$$$) {
    my ($prj,$handleFile,$htmlFile,$idHtmlTag,$title,$data) = @_;
    my %Values = %$data;
    if(open $handleFile,">>$htmlFile") {
            print $handleFile '
        <script type="text/javascript">
$(function () {
    $(\'#',$idHtmlTag,'\').highcharts({
        chart: {
            type: \'pie\',
            options3d: {
                enabled: true,
                alpha: 45,
                beta: 0
            }
        },
        title: {
            text: \'',$title,'\'
        },
        tooltip: {
            pointFormat: \'{series.name}: <b>{point.percentage:.1f}%</b>\'
        },
        plotOptions: {
            pie: {
                allowPointSelect: true,
                cursor: \'pointer\',
                depth: 35,
                dataLabels: {
                    enabled: true,
                    format: \'{point.name}\'
                }
            }
        },
        series: [{
            type: \'pie\',
            name: \''.$prj.'\',
            data: [';
        ### insert datas
            foreach my $string (keys %Values) {
                my ($value,$indice) = split ',',$Values{$string};
                if($indice == 0) {
                    print $handleFile '
                [\'',$string,'\',   ',$value,'],';
                }
                else {
                    print $handleFile '
                {
                    name: \'',$string,'\',
                    y: ',$value,',
                    sliced: true,
                    selected: true
                },';
            }
        } # endif foreach
            print $handleFile '
            ]
        }]
    });
});
        </script>
';
        sap_sm_print_div($handleFile,$idHtmlTag);
    }
    close $handleFile;
}

sub sap_sm_line_chart($$$$$$$$) {
    my ($prj,$handleFile,$htmlFile,$idHtmlTag,$title,$yAxis,$labels,$data)
        = @_;

    if(open $handleFile,">>$htmlFile") {
        my %Values = %$data;
        my $lineLabels = join ",",@$labels;
        ($lineLabels) =~ s-\,-\'\,\'-g;
        print $handleFile '
        <script type="text/javascript">
$(function () {
    $(\'#',$idHtmlTag,'\').highcharts({
            chart: {
                type: \'line\'
            },
            title: {
                text: \'',$title,'\'
            },
            subtitle: {
                text: \'Source: '.$prj.'\'
            },
            xAxis: {
                categories: [\'',$lineLabels,'\']
            },
            yAxis: {
                title: {
                    text: \'',$yAxis,'\'
                }
            },
            plotOptions: {
                line: {
                    dataLabels: {
                        enabled: true
                    },
                    enableMouseTracking: false
                }
            },
            series: [';
        foreach my $label (keys %Values) {
            my $listOfValues = join ",",@{$Values{$label}};
            print $handleFile '
            {
                name: \'',$label,'\',
                data: [',$listOfValues,'],
            },';
            }
        print $handleFile '
            ]
    });
});
        </script>
';
        sap_sm_print_div($handleFile,$idHtmlTag);
        close $handleFile;
    }
}

sub sap_sm_line_chart_hms($$$$$$$$) {
    my ($prj,$handleFile,$htmlFile,$idHtmlTag,$title,$yAxis,$labels,$data)
        = @_;

    if(open $handleFile,">>$htmlFile") {
        my %Values = %$data;
        my $lineLabels = join ",",@$labels;
        ($lineLabels) =~ s-\,-\'\,\'-g;
        print $handleFile '
        <script type="text/javascript">
$(function () {
    $(\'#',$idHtmlTag,'\').highcharts({
            chart: {
                type: \'line\'
            },
            title: {
                text: \'',$title,'\'
            },
            subtitle: {
                text: \'Source: '.$prj.'\'
            },
            xAxis: {
                categories: [\'',$lineLabels,'\']
            },
            yAxis: {
                type: \'datetime\',
                dateTimeLabelFormats: {
                   minute: \'%H:%M:%S\'
                },
                title: {
                    text: \'',$yAxis,'\'
                }
            },
            tooltip: {
                pointFormat: \'<span style="color:{point.color}">\u25CF</span> {series.name}: <b>{point.y: %H:%M:%S}</b><br/>\'
            },
            series: [';
        foreach my $label (keys %Values) {
            my $listOfValues = join ",",@{$Values{$label}};
            print $handleFile '
            {
                name: \'',$label,'\',
                data: [',$listOfValues,'],
                dataLabels: {
                    enabled: false,
                    formatter: function() {
                        var time = this.y / 1000;
                        var hours1 = parseInt(time / 3600);
                        var mins1 = parseInt((parseInt(time % 3600)) / 60);
                        return (hours1 < 10 ? \'0\' + hours1 : hours1) + \':\' + (mins1 < 10 ? \'0\' + mins1 : mins1);
                    }
                }
            },';
            }
        print $handleFile '
            ]
    });
});
        </script>
';
        sap_sm_print_div($handleFile,$idHtmlTag);
        close $handleFile;
    }
}

sub sap_sm_drill_pie_chart($$$$$$) {
        my ($prj,$handleFile,$htmlFile,$idHtmlTag1,$idHtmlTag2,$title)
            = @_;
        if(open $handleFile,">>$htmlFile") {
            print $handleFile '
<script type="text/javascript">
$(function () {

    Highcharts.data({
        csv: document.getElementById(\'',$idHtmlTag1,'\').innerHTML,
        itemDelimiter: \'\\t\',
        parsed: function (columns) {

            var brands = {},
                brandsData = [],
                versions = {},
                drilldownSeries = [];
            
            // Parse percentage strings
            columns[1] = $.map(columns[1], function (value) {
                if (value.indexOf(\'\%\') === value.length - 1) {
                    value = parseFloat(value);
                }
                return value;
            });

            $.each(columns[0], function (i, name) {
                var brand,
                    version;

                if (i > 0) {

                    // Remove special edition notes
                    name = name.split(\' -\')[0];

                    // Split into brand and version
                    version = name.match(/([0-9]+[.0-9x]*)/);
                    if (version) {
                        version = version[0];
                    }
                    brand = name.replace(version, \'\');

                    // Create the main data
                    if (!brands[brand]) {
                        brands[brand] = columns[1][i];
                    } else {
                        brands[brand] += columns[1][i];
                    }

                    // Create the version data
                    if (version !== null) {
                        if (!versions[brand]) {
                            versions[brand] = [];
                        }
                        versions[brand].push([\'v\' + version, columns[1][i]]);
                    }
                }
                
            });

            $.each(brands, function (name, y) {
                brandsData.push({ 
                    name: name, 
                    y: y,
                    drilldown: versions[name] ? name : null
                });
            });
            $.each(versions, function (key, value) {
                drilldownSeries.push({
                    name: key,
                    id: key,
                    data: value
                });
            });

            // Create the chart
            $(\'#',$idHtmlTag2,'\').highcharts({
                chart: {
                    type: \'pie\'
                },
                title: {
                    text: \'',$title,'\'
                },
                subtitle: {
                    text: \'Click the slices to view versions. Source: '.$prj.'\'
                },
                plotOptions: {
                    series: {
                        dataLabels: {
                            enabled: true,
                            format: \'{point.name}: {point.y:.2f}\%\'
                        }
                    }
                },

                tooltip: {
                    headerFormat: \'<span style="font-size:11px">{series.name}</span><br>\',
                    pointFormat: \'<span style="color:{point.color}">{point.name}</span>: <b>{point.y:.2f}\%</b> of total<br/>\'
                }, 

                series: [{
                    name: \'Brands\',
                    colorByPoint: true,
                    data: brandsData
                }],
                drilldown: {
                    series: drilldownSeries
                }
            })

        }
    });
});
        </script>
';
            #&sap_sm_print_div($handleFile,$idHtmlTag);
            print $handleFile '
        <div id="',$idHtmlTag2,'" style="min-width: 310px; max-width: 600px; height: 400px; margin: 0 auto"></div>
        <pre id="',$idHtmlTag1,'" style="display:none">
';
        close $handleFile;
    }
}

sub sap_sm_vertical_bar_graph($$$$$$) {
    my ($handleFile,$htmlFile,$idHtmlTag,$title,$yAxis,$labels,$data)
        = @_;
    if(open $handleFile,">>$htmlFile") {
        my %Values = %$data;
        my $lineLabels = join ",",@$labels;
        ($lineLabels) =~ s-\,-\'\,\'-g;
        print $handleFile '
        <script type="text/javascript">
$(function () {
        $(\'#',$idHtmlTag,'\').highcharts({
            chart: {
                type: \'column\'
            },
            title: {
                text: \'',$title,' \'
            },
            xAxis: {
                categories: [\'',$lineLabels,'\']
            },
            yAxis: {
                allowDecimals: false,
                min: 0,
                title: {
                    text: \'',$yAxis,'\'
                }
            },
            tooltip: {
                formatter: function() {
                    return \'<b>\'+ this.x +\'</b><br/>\'+
                        this.series.name +\': \'+ this.y +\'<br/>\'+
                        \'Total: \'+ this.point.stackTotal;
                }
            },
            plotOptions: {
                column: {
                    stacking: \'normal\'
                }
            },
            series: [
';
        foreach my $label (keys %Values) {
            my $listOfValues = join ",",@{$Values{$label}};
            print $handleFile '
            {
                name: \'',$label,'\',
                data: [',$listOfValues,'],
                stack: \'male\'
            },';
            }
        print $handleFile '
            ]
    });
});
        </script>
';
        sap_sm_print_div($handleFile,$idHtmlTag);
        close $handleFile;
    }
}

sub sap_sm_horizonral_bar_graph($$$$$$$) {
    my ($handleFile,$htmlFile,$idHtmlTag,$title,$yAxis,$labels,$data)
        = @_;
    if(open $handleFile,">>$htmlFile") {
        my %Values = %$data;
        my $lineLabels = join ",",@$labels;
        ($lineLabels) =~ s-\,-\'\,\'-g;
        print $handleFile '
        <script type="text/javascript">
$(function () {
        $(\'#',$idHtmlTag,'\').highcharts({
            chart: {
                type: \'bar\'
            },
            title: {
                text: \'',$title,' \'
            },
            xAxis: {
                categories: [\'',$lineLabels,'\']
            },
            yAxis: {
                min: 0,
                title: {
                    text: \'',$yAxis,'\'
                }
            },
            legend: {
                reversed: true
            },
            plotOptions: {
                series: {
                    stacking: \'normal\'
                }
            },
            series: [
';
        foreach my $label (keys %Values) {
            my $listOfValues = join ",",@{$Values{$label}};
            print $handleFile '
            {
                name: \'',$label,'\',
                data: [',$listOfValues,'],
                stack: \'male\'
            },';
            }
        print $handleFile '
            ]
    });
});
        </script>
';
        sap_sm_print_div($handleFile,$idHtmlTag);
        close $handleFile;
    }
}

sub sap_sm_print_div($$) {
    my ($handleFile,$idHtmlTag) = @_ ;
    print $handleFile "     <center><div id=\"$idHtmlTag\" style=\"min-width: 300px; height: 500px; margin: 0 auto\"></div></center><br/>\n";
}

1;
