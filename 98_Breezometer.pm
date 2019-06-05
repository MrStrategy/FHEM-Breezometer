package main;

use strict;
use warnings;
use Data::Dumper;
use utf8;
use Encode qw( encode_utf8 );
use Scalar::Util qw(looks_like_number);
use HttpUtils;
use JSON;

my %Breezometer_gets = (
update => " ",
updateForecast => " ",
updatePollenData => " ");

my %Breezometer_sets = (
start	=> " ",
stop => " ",
interval => " "
);

my %Breezometer_url = (
getCurrentAirQuality          => 'https://api.breezometer.com/air-quality/v2/current-conditions?lat=#latitude#&lon=#longitude#&key=#apikey#&features=#features#',
getHourlyForecastAirQuality   => 'https://api.breezometer.com/air-quality/v2/forecast/hourly?lat=#latitude#&lon=#longitude#&key=#apikey#&hours=#forecastHours#&features=#features#',
getHourlyHistoryAirQuality    => 'https://api.breezometer.com/air-quality/v2/historical/hourly?lat=#latitude#&lon=#longitude#&key=#apikey#&features=#features#&hours=#forecastHours#',
getCurrentPollenData              => 'https://api.breezometer.com/pollen/v2/current-conditions?lat=#latitude#&lon=#longitude#&key=#apikey#&features=#features#' ,
getDailyForecastPollenData        => 'https://api.breezometer.com/pollen/v2/forecast/daily?lat=#latitude#&lon=#longitude#&key=#apikey#&features=#features#&days=#forecastDays#',
getCurrentWeather             => 'https://api.breezometer.com/weather/v1/current-conditions?lat=#latitude#&lon=#longitude#&key=#apikey#',
getHourlyWeatherForecast      =>  'https://api.breezometer.com/weather/v1/forecast/hourly?lat=#latitude#&lon=#longitude#&key=#apikey#&hours=#forecastHours#',
getDailyWeatherForecast       =>  'https://api.breezometer.com/weather/v1/forecast/daily?lat=#latitude#&lon=#longitude#&key=#apikey#&days=#forecastDays#'
);


sub Breezometer_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}      = 'Breezometer_Define';
	$hash->{UndefFn}    = 'Breezometer_Undef';
	$hash->{SetFn}      = 'Breezometer_Set';
	$hash->{GetFn}      = 'Breezometer_Get';
	$hash->{AttrFn}     = 'Breezometer_Attr';
	$hash->{ReadFn}     = 'Breezometer_Read';
	$hash->{AttrList} =
	'show_HealthRecommendations:yes,no '
	.	'show_PollutionDetails:yes,no '
	. 'show_PollutionEffects:yes,no '
	. 'show_PollutionSources:yes,no '
	. 'show_PollutionConcentration:yes,no '
	. $readingFnAttributes;

	Log 3, "Breezometer module initialized.";
}


sub Breezometer_Define($$)
{
	my ($hash, $def) = @_;
	my @param = split("[ \t]+", $def);
	my $name = $hash->{NAME};

	Log3 $name, 3, "Breezometer_Define $name: called ";

	my $errmsg = '';

	# Check parameter(s) - Must be min 5 in total (counts strings not purly parameter, interval is optional)
	if( int(@param) < 5 ) {
		$errmsg = return "syntax error: define <name> Breezometer <longitude> <latitude> <apikey> [Interval]";
		Log3 $name, 1, "Breezometer $name: " . $errmsg;
		return $errmsg;
	}

	#Check if longitude is a valid number
	if ( looks_like_number($param[2])  && $param[2] >= -180 && $param[2] <= 180) {
		$hash->{Longitude} = $param[2];
	} else {
		$errmsg = "specify valid value for longitude. Longitude must be between -180 and 180.";
		Log3 $name, 1, "Breezometer $name: " . $errmsg;
		return $errmsg;
	}

	#Check if latitude is a valid number
	if ( looks_like_number($param[3])  && $param[3] >= -90 && $param[3] <= 90) {
		$hash->{Latitude} = $param[3];
	} else {
		$errmsg = "specify valid value for latitude. Latitude must be between -90 and 90.";
		Log3 $name, 1, "Breezometer $name: " . $errmsg;
		return $errmsg;
	}


	$hash->{API_Key} = $param[4];

	if (defined $param[5]) {
		$hash->{DEF} = sprintf("%s %s %s %s", $param[2], $param[3], $param[4], $param[5]);
	} else {
		$hash->{DEF} = sprintf("%s %s %s", $param[2], $param[3], $param[4]);
	}

	#Check if interval is set and numeric.
	#If not set -> set to 60 minutes
	#If less then 10 minutes set to 10
	#If not an integer abort with failure.
	my $interval = 60;
	if (defined $param[5]) {
		if ( $param[5] =~ /^\d+$/ ) {
			$interval = $param[5];
		} else {
			$errmsg = "Specify valid integer value for interval. Whole numbers > 10 only.";
			Log3 $name, 1, "Breezometer $name: " . $errmsg;
			return $errmsg;
		}
	}

	if( $interval < 10 ) { $interval = 10; }
	$hash->{INTERVAL} = $interval;

	readingsSingleUpdate($hash,'state','Undefined',0);

	RemoveInternalTimer($hash);
	return undef;
}


sub Breezometer_Undef($$)
{
	my ($hash,$arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}


sub Breezometer_httpSimpleOperation($$$;$)
{
	my ($hash,$url, $operation, $message) = @_;
	my ($json,$err,$data,$decoded);
	my $name = $hash->{NAME};

	my $request = {
		url           => $url,
		header        => "Content-Type:application/json;charset=UTF-8",
		method        => $operation,
		timeout       =>  2,
		hideurl       =>  1
	};

	$request->{data} = $message if (defined $message);
	Log3 $name, 5, 'Request: ' . Dumper($request);

	($err,$data)    = HttpUtils_BlockingGet($request);

	$json = "" if( !$json );
	$data = "" if( !$data );
	Log3 $name, 4, "FHEM -> Tado: " . $url;
	Log3 $name, 4, "FHEM -> Tado: " . $message if (defined $message);
	Log3 $name, 4, "Tado -> FHEM: " . $data if (defined $data);
	Log3 $name, 4, "Tado -> FHEM: Got empty response."  if (not defined $data);
	Log3 $name, 5, '$err: ' . $err;
	Log3 $name, 5, "method: " . $operation;
	Log3 $name, 2, "Something gone wrong" if( $data =~ "/tadoMode/" );

	$err = 1 if( $data =~ "/tadoMode/" );
	if (defined $data and (not $data eq '') and $operation ne 'DELETE') {
		eval {
			$decoded  = decode_json($data) if( !$err );
			Log3 $name, 5, 'Decoded: ' . Dumper($decoded);
			return $decoded;
		} or do  {
			Log3 $name, 5, 'Failure decoding: ' . $@;
		}
	} else {
		return undef;
	}
}


sub Breezometer_Get($@)
{
	my ( $hash, $name, @args ) = @_;

	return '"get Breezometer" needs at least one argument' if (int(@args) < 1);

	my $opt = shift @args;
	if(!$Breezometer_gets{$opt}) {
		my @cList = keys %Breezometer_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}

	my $cmd = $args[0];
	my $arg = $args[1];

	if($opt eq "update"){

		return Breezometer_RequestUpdateCurrentAirQuality($hash);

	}	elsif($opt eq "updateForecast"){

			return Breezometer_RequestUpdateAirQualityHourlyForecast($hash);

	}	elsif($opt eq "updatePollenData"){

      return Breezometer_RequestUpdateCurrentPollenData($hash);

	}  else	{

		my @cList = keys %Breezometer_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
}


sub Breezometer_Set($@)
{
	my ($hash, $name, @param) = @_;

	return '"set $name" needs at least one argument' if (int(@param) < 1);

	my $opt = shift @param;
	my $value = join("", @param);

	if(!defined($Breezometer_sets{$opt})) {
		my @cList = keys %Breezometer_sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}

	if ($opt eq "start")	{

		readingsSingleUpdate($hash,'state','Started',0);
		RemoveInternalTimer($hash);

		$hash->{LOCAL} = 1;
		Breezometer_RequestZoneUpdate($hash);
		delete $hash->{LOCAL};

		InternalTimer(gettimeofday()+ InternalVal($name,'INTERVAL', undef), "Breezometer_UpdateDueToTimer", $hash);

		Log3 $name, 1, sprintf("Breezometer_Set %s: Updated readings and started timer to automatically update readings with interval %s", $name, InternalVal($name,'INTERVAL', undef));


	} elsif ($opt eq "stop"){

		RemoveInternalTimer($hash);
		Log3 $name, 1, "Breezometer_Set $name: Stopped the timer to automatically update readings";
		readingsSingleUpdate($hash,'state','Initialized',0);
		return undef;

	} elsif ($opt eq "interval"){

		my $interval = shift @param;

		$interval= 60 unless defined($interval);
		if( $interval < 5 ) { $interval = 5; }

		Log3 $name, 1, "Breezometer_Set $name: Set interval to" . $interval;

		$hash->{INTERVAL} = $interval;
	}
}


sub Breezometer_Attr(@)
{
	return undef;
}


sub Breezometer_UpdateCurrentAirQualityCallback($)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
	{
		Log3 $name, 3, "error while requesting ".$param->{url}." - $err";                                               # Eintrag fürs Log
		readingsSingleUpdate($hash, "state", "ERROR", 1);
		return undef;
	}

	Log3 $name, 3, "Received non-blocking data from Breezometer.";

	Log3 $name, 4, "FHEM -> Breezometer: " . $param->{url};
	Log3 $name, 4, "FHEM -> Breezometer: " . $param->{message} if (defined $param->{message});
	Log3 $name, 4, "Breezometer -> FHEM: " . $data;
	Log3 $name, 5, '$err: ' . $err;
	Log3 $name, 5, "method: " . $param->{method};
	Log3 $name, 2, "Something gone wrong" if( $data =~ "/data/" );

	if (!defined($data) or $param->{method} eq 'DELETE') {
		return undef;
	}

	eval {
		my $d  = decode_json($data) if( !$err );
		Log3 $name, 5, 'Decoded: ' . Dumper($d);

		if (defined $d && ref($d) eq "HASH" && defined $d->{error}){
			log 1, Dumper $d;
			readingsSingleUpdate($hash,'state',"Error: $d->{error}" ,1);
			return undef;
		}

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "LastUpdate_CurrentAirQuality", localtime );

    readingsBulkUpdate($hash, "Breezometer_AirQualityIndex", $d->{data}->{indexes}->{baqi}->{'aqi_display'} );
		readingsBulkUpdate($hash, "Breezometer_AirQuality_Category", $d->{data}->{indexes}->{baqi}->{category} );
    readingsBulkUpdate($hash, "Breezometer_AirQuality_DominantPollutant", $d->{data}->{indexes}->{baqi}->{"dominant_pollutant"} );

		readingsBulkUpdate($hash, "LuQx_AirQualityIndex", $d->{data}->{indexes}->{deu_lubw}->{'aqi_display'} );
		readingsBulkUpdate($hash, "LuQx_AirQuality_Category", $d->{data}->{indexes}->{deu_lubw}->{category} );
		readingsBulkUpdate($hash, "LuQx_AirQuality_DominantPollutant", $d->{data}->{indexes}->{deu_lubw}->{"dominant_pollutant"} );

		my $showHealthRecommendations = AttrVal($name, 'show_HealthRecommendations', 'no');
		if ($showHealthRecommendations eq 'yes')
		{
    readingsBulkUpdate($hash, "HealthRecommendation_General_Population", $d->{data}->{"health_recommendations"}->{"general_population"} );
		readingsBulkUpdate($hash, "HealthRecommendation_Elderly", $d->{data}->{"health_recommendations"}->{"elderly"} );
		readingsBulkUpdate($hash, "HealthRecommendation_Lung_Diseases", $d->{data}->{"health_recommendations"}->{"lung_diseases"} );
		readingsBulkUpdate($hash, "HealthRecommendation_Hearth_Diseases", $d->{data}->{"health_recommendations"}->{"heart_diseases"} );
		readingsBulkUpdate($hash, "HealthRecommendation_Active", $d->{data}->{"health_recommendations"}->{"active"} );
		readingsBulkUpdate($hash, "HealthRecommendation_Pregnant_Woman", $d->{data}->{"health_recommendations"}->{"pregnant_women"} );
		readingsBulkUpdate($hash, "HealthRecommendation_Children", $d->{data}->{"health_recommendations"}->{"children"} );
		}

		my $showPollutionDetails = AttrVal($name, 'show_PollutionDetails', 'no');
		if ($showPollutionDetails eq 'yes')
		{
			readingsBulkUpdate($hash, "Breezometer_Pollution_CO_FullName", $d->{data}->{pollutants}->{co}->{full_name} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_CO_AirQualityIndex", $d->{data}->{pollutants}->{co}->{"aqi_information"}->{baqi}->{aqi_display} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_CO_Category", $d->{data}->{pollutants}->{co}->{"aqi_information"}->{baqi}->{category} );

			readingsBulkUpdate($hash, "Breezometer_Pollution_NO2_FullName", $d->{data}->{pollutants}->{no2}->{full_name} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_NO2_AirQualityIndex", $d->{data}->{pollutants}->{no2}->{"aqi_information"}->{baqi}->{aqi_display} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_NO2_Category", $d->{data}->{pollutants}->{no2}->{"aqi_information"}->{baqi}->{category} );

			readingsBulkUpdate($hash, "Breezometer_Pollution_O3_FullName", $d->{data}->{pollutants}->{o3}->{full_name} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_O3_AirQualityIndex", $d->{data}->{pollutants}->{o3}->{"aqi_information"}->{baqi}->{aqi_display} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_O3_Category", $d->{data}->{pollutants}->{o3}->{"aqi_information"}->{baqi}->{category} );

			readingsBulkUpdate($hash, "Breezometer_Pollution_PM10_FullName", $d->{data}->{pollutants}->{pm10}->{full_name} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM10_AirQualityIndex", $d->{data}->{pollutants}->{pm10}->{"aqi_information"}->{baqi}->{aqi_display} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM10_Category", $d->{data}->{pollutants}->{pm10}->{"aqi_information"}->{baqi}->{category} );

			readingsBulkUpdate($hash, "Breezometer_Pollution_PM25_FullName", $d->{data}->{pollutants}->{pm25}->{full_name} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM25_AirQualityIndex", $d->{data}->{pollutants}->{pm25}->{"aqi_information"}->{baqi}->{aqi_display} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM25_Category", $d->{data}->{pollutants}->{pm25}->{"aqi_information"}->{baqi}->{category} );

			readingsBulkUpdate($hash, "Breezometer_Pollution_SO2_FullName", $d->{data}->{pollutants}->{so2}->{full_name} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_SO2_AirQualityIndex", $d->{data}->{pollutants}->{so2}->{"aqi_information"}->{baqi}->{aqi_display} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_SO2_Category", $d->{data}->{pollutants}->{so2}->{"aqi_information"}->{baqi}->{category} );
		}

		my $showPollutionSources = AttrVal($name, 'show_PollutionSources', 'no');

		if ($showPollutionSources eq 'yes'  )
		{
			readingsBulkUpdate($hash, "Pollution_CO_Source", $d->{data}->{pollutants}->{co}->{"sources_and_effects"}->{sources} );
			readingsBulkUpdate($hash, "Pollution_NO2_Source", $d->{data}->{pollutants}->{no2}->{"sources_and_effects"}->{sources} );
			readingsBulkUpdate($hash, "Pollution_O3_Source", $d->{data}->{pollutants}->{o3}->{"sources_and_effects"}->{sources} );
			readingsBulkUpdate($hash, "Pollution_PM10_Source", $d->{data}->{pollutants}->{pm10}->{"sources_and_effects"}->{sources} );
			readingsBulkUpdate($hash, "Pollution_PM25_Source", $d->{data}->{pollutants}->{pm25}->{"sources_and_effects"}->{sources} );
			readingsBulkUpdate($hash, "Pollution_SO2_Source", $d->{data}->{pollutants}->{so2}->{"sources_and_effects"}->{sources} );
		}


    my $showPollutionEffects = AttrVal($name, 'show_PollutionEffects', 'no');
		if ($showPollutionEffects eq 'yes' )
		{
			readingsBulkUpdate($hash, "Pollution_CO_Effect", $d->{data}->{pollutants}->{co}->{"sources_and_effects"}->{effects} );
			readingsBulkUpdate($hash, "Pollution_NO2_Effect", $d->{data}->{pollutants}->{no2}->{"sources_and_effects"}->{effects} );
			readingsBulkUpdate($hash, "Pollution_O3_Effect", $d->{data}->{pollutants}->{o3}->{"sources_and_effects"}->{effects} );
			readingsBulkUpdate($hash, "Pollution_PM10_Effect", $d->{data}->{pollutants}->{pm10}->{"sources_and_effects"}->{effects} );
			readingsBulkUpdate($hash, "Pollution_PM25_Effect", $d->{data}->{pollutants}->{pm25}->{"sources_and_effects"}->{effects} );
			readingsBulkUpdate($hash, "Pollution_SO2_Effect", $d->{data}->{pollutants}->{so2}->{"sources_and_effects"}->{effects} );
		}

		my $showPollutionConcentration = AttrVal($name, 'show_PollutionConcentration', 'no');
		if ($showPollutionConcentration eq 'yes')
		{
			readingsBulkUpdate($hash, "Breezometer_Pollution_CO_Concentration", $d->{data}->{pollutants}->{co}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_CO_Concentration_Unit", $d->{data}->{pollutants}->{co}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_NO2_Concentration", $d->{data}->{pollutants}->{no2}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_NO2_Concentration_Unit", $d->{data}->{pollutants}->{no2}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_O3_Concentration", $d->{data}->{pollutants}->{o3}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_O3_Concentration_Unit", $d->{data}->{pollutants}->{o3}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM10_Concentration", $d->{data}->{pollutants}->{pm10}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM10_Concentration_Unit", $d->{data}->{pollutants}->{pm10}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM25_Concentration", $d->{data}->{pollutants}->{pm25}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_PM25_Concentration_Unit", $d->{data}->{pollutants}->{pm25}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_SO2_Concentration", $d->{data}->{pollutants}->{so2}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Breezometer_Pollution_SO2_Concentration_Unit", $d->{data}->{pollutants}->{so2}->{concentration}->{units} );
		}

		readingsEndUpdate($hash, 1);
    readingsSingleUpdate($hash,'state',"Initialized",0);

		return undef;
	} or do  {
		Log3 $name, 5, 'Failure decoding: ' . $@;
		return undef;
	}
}

sub Breezometer_RequestUpdateCurrentAirQuality($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (not defined $hash){
		Log3 $name, 1, "Error on Breezometer_RequestUpdate. Missing hash variable";
		return undef;
	}

	Log3 $name, 4, "Breezometer_RequestUpdate Called for non-blocking value update. Name: $name";


		my $readTemplate = $Breezometer_url{"getCurrentAirQuality"};

    my $longitude = InternalVal($name,'Longitude', undef);
		$readTemplate =~ s/#longitude#/$longitude/g;
		my $latitude = InternalVal($name,'Latitude', undef);
		$readTemplate =~ s/#latitude#/$latitude/g;
		my $apiKey = InternalVal($name,'API_Key', undef);
		$readTemplate =~ s/#apikey#/$apiKey/g;
    $readTemplate =~ s/#features#/breezometer_aqi,local_aqi/g;


		my $showHealthRecommendations = AttrVal($name, 'show_HealthRecommendations', 'no');
		if ($showHealthRecommendations eq 'yes')
		{
			$readTemplate .= ',health_recommendations'
		}

		my $showPollutionDetails = AttrVal($name, 'show_PollutionDetails', 'no');
		if ($showPollutionDetails eq 'yes')
		{
			$readTemplate .= ',pollutants_aqi_information'
		}

		my $showPollutionSources = AttrVal($name, 'show_PollutionSources', 'no');
		my $showPollutionEffects = AttrVal($name, 'show_PollutionEffects', 'no');
		if ($showPollutionSources eq 'yes' || $showPollutionEffects eq 'yes' )
		{
			$readTemplate .= ',sources_and_effects'
		}

		my $showPollutionConcentration = AttrVal($name, 'show_PollutionConcentration', 'no');
		if ($showPollutionConcentration eq 'yes')
		{
			$readTemplate .= ',pollutants_concentrations'
		}



		my $request = {
			url           => $readTemplate,
			header        => "Content-Type:application/json;charset=UTF-8",
			method        => 'GET',
			timeout       =>  2,
			hideurl       =>  1,
			callback      => \&Breezometer_UpdateCurrentAirQualityCallback,
			hash          => $hash
		};

		Log3 $name, 5, 'NonBlocking Request: ' . Dumper($request);

		HttpUtils_NonblockingGet($request);
    readingsSingleUpdate($hash,'state',"Request running",0);

		return undef;
}


sub Breezometer_UpdateAirQualityHourlyForecast($)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
	{
		Log3 $name, 3, "error while requesting ".$param->{url}." - $err";                                               # Eintrag fürs Log
		readingsSingleUpdate($hash, "state", "ERROR", 1);
		return undef;
	}

	Log3 $name, 3, "Received non-blocking data from Breezometer.";

	Log3 $name, 4, "FHEM -> Breezometer: " . $param->{url};
	Log3 $name, 4, "FHEM -> Breezometer: " . $param->{message} if (defined $param->{message});
	Log3 $name, 4, "Breezometer -> FHEM: " . $data;
	Log3 $name, 5, '$err: ' . $err;
	Log3 $name, 5, "method: " . $param->{method};
	Log3 $name, 2, "Something gone wrong" if( $data =~ "/data/" );

	if (!defined($data) or $param->{method} eq 'DELETE') {
		return undef;
	}

	eval {
		my $d  = decode_json($data) if( !$err );
		Log3 $name, 5, 'Decoded: ' . Dumper($d);

		if (defined $d && ref($d) eq "HASH" && defined $d->{error}){
			log 1, Dumper $d;
			readingsSingleUpdate($hash,'state',"Error: $d->{error}->{title}" ,1);
			return undef;
		}

		for (my $i=0 ; $i < scalar @{$d->{data}}; $i++)
		{

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "LastUpdate_AirQualityForecast", localtime );

		my $j = $i+1;

    my $year = substr( $d->{data}[$i]->{datetime} , 0, 4);
		my $month = substr( $d->{data}[$i]->{datetime} , 5, 2);
		my $day = substr( $d->{data}[$i]->{datetime} , 8, 2);
    my $hour = substr( $d->{data}[$i]->{datetime} , 11, 2);
		my $min = substr( $d->{data}[$i]->{datetime} , 14, 2);
		my $sec = substr( $d->{data}[$i]->{datetime} , 17, 2);

    my $forecastTime = fhemTimeGm($sec, $min, $hour, $day, $month-1, $year-1900);

    readingsBulkUpdate($hash, "Forecast_".$j."h_Time", FmtDateTime($forecastTime) );

    readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_AirQualityIndex", $d->{data}[$i]->{indexes}->{baqi}->{'aqi_display'} );
		readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_AirQuality_Category", $d->{data}[$i]->{indexes}->{baqi}->{category} );
    readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_AirQuality_DominantPollutant", $d->{data}[$i]->{indexes}->{baqi}->{"dominant_pollutant"} );

		readingsBulkUpdate($hash, "Forecast_".$j."h_LuQx_AirQualityIndex", $d->{data}[$i]->{indexes}->{deu_lubw}->{'aqi_display'} );
		readingsBulkUpdate($hash, "Forecast_".$j."h_LuQx_AirQuality_Category", $d->{data}[$i]->{indexes}->{deu_lubw}->{category} );
		readingsBulkUpdate($hash, "Forecast_".$j."h_LuQx_AirQuality_DominantPollutant", $d->{data}[$i]->{indexes}->{deu_lubw}->{"dominant_pollutant"} );


		my $showPollutionConcentration = AttrVal($name, 'show_PollutionConcentration', 'no');
		if ($showPollutionConcentration eq 'yes')
		{
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_CO_Concentration", $d->{data}[$i]->{pollutants}->{co}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_CO_Concentration_Unit", $d->{data}[$i]->{pollutants}->{co}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_NO2_Concentration", $d->{data}[$i]->{pollutants}->{no2}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_NO2_Concentration_Unit", $d->{data}[$i]->{pollutants}->{no2}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_O3_Concentration", $d->{data}[$i]->{pollutants}->{o3}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_O3_Concentration_Unit", $d->{data}[$i]->{pollutants}->{o3}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_PM10_Concentration", $d->{data}[$i]->{pollutants}->{pm10}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_PM10_Concentration_Unit", $d->{data}[$i]->{pollutants}->{pm10}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_PM25_Concentration", $d->{data}[$i]->{pollutants}->{pm25}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_PM25_Concentration_Unit", $d->{data}[$i]->{pollutants}->{pm25}->{concentration}->{units} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_SO2_Concentration", $d->{data}[$i]->{pollutants}->{so2}->{concentration}->{value} );
			readingsBulkUpdate($hash, "Forecast_".$j."h_Breezometer_Pollution_SO2_Concentration_Unit", $d->{data}[$i]->{pollutants}->{so2}->{concentration}->{units} );
		}
    }

		readingsEndUpdate($hash, 1);

    readingsSingleUpdate($hash,'state',"Initialized",0);

		return undef;
	} or do  {
		Log3 $name, 5, 'Failure decoding: ' . $@;
		return undef;
	}
}

sub Breezometer_RequestUpdateAirQualityHourlyForecast($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (not defined $hash){
		Log3 $name, 1, "Error on Breezometer_RequestUpdate. Missing hash variable";
		return undef;
	}

	Log3 $name, 4, "Breezometer_RequestUpdate Called for non-blocking value update. Name: $name";


		my $readTemplate = $Breezometer_url{"getHourlyForecastAirQuality"};

    my $longitude = InternalVal($name,'Longitude', undef);
		$readTemplate =~ s/#longitude#/$longitude/g;
		my $latitude = InternalVal($name,'Latitude', undef);
		$readTemplate =~ s/#latitude#/$latitude/g;
		my $apiKey = InternalVal($name,'API_Key', undef);
		$readTemplate =~ s/#apikey#/$apiKey/g;
    $readTemplate =~ s/#features#/breezometer_aqi,local_aqi/g;


		my $showPollutionConcentration = AttrVal($name, 'show_PollutionConcentration', 'no');
		if ($showPollutionConcentration eq 'yes')
		{
			$readTemplate .= ',pollutants_concentrations'
		}

		my $pollutionForecastInHours = AttrVal($name, 'PollutionForecast_Hours', '3');
	  $readTemplate =~ s/#forecastHours#/$pollutionForecastInHours/g;


		my $request = {
			url           => $readTemplate,
			header        => "Content-Type:application/json;charset=UTF-8",
			method        => 'GET',
			timeout       =>  2,
			hideurl       =>  1,
			callback      => \&Breezometer_UpdateAirQualityHourlyForecast,
			hash          => $hash
		};

		Log3 $name, 5, 'NonBlocking Request: ' . Dumper($request);

		HttpUtils_NonblockingGet($request);
    readingsSingleUpdate($hash,'state',"Request running",0);
		return undef;
}


sub Breezometer_UpdateCurrentPollenDataCallback($)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
	{
		Log3 $name, 3, "error while requesting ".$param->{url}." - $err";                                               # Eintrag fürs Log
		readingsSingleUpdate($hash, "state", "ERROR", 1);
		return undef;
	}

	Log3 $name, 3, "Received non-blocking data from Breezometer.";

	Log3 $name, 4, "FHEM -> Breezometer: " . $param->{url};
	Log3 $name, 4, "FHEM -> Breezometer: " . $param->{message} if (defined $param->{message});
	Log3 $name, 4, "Breezometer -> FHEM: " . $data;
	Log3 $name, 5, '$err: ' . $err;
	Log3 $name, 5, "method: " . $param->{method};
	Log3 $name, 2, "Something gone wrong" if( $data =~ "/data/" );

	if (!defined($data) or $param->{method} eq 'DELETE') {
		return undef;
	}

	eval {
		my $d  = decode_json($data) if( !$err );
		Log3 $name, 5, 'Decoded: ' . Dumper($d);

		if (defined $d && ref($d) eq "HASH" && defined $d->{error}){
			log 1, Dumper $d;
			readingsSingleUpdate($hash,'state',"Error: $d->{error}" ,1);
			return undef;
		}

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "LastUpdate_CurrentPollenData", localtime );
   my @list = ('grass', 'tree', 'weed');
		foreach my $entry ( @list)
		{
			readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s",$entry), $d->{data}->{types}->{$entry}->{index}->{value} );
			readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s_Category",$entry), $d->{data}->{types}->{$entry}->{index}->{category} );
	    readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s_InSeason",$entry), $d->{data}->{types}->{$entry}->{"in_season"} );
			readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s_DataAvailable",$entry), $d->{data}->{types}->{$entry}->{"data_available"} );
		}

   @list = ('alder', 'ash', 'birch', 'cottenwood', 'elm', 'maple', 'olive', 'juniper', 'jpn_cedar_cypress', 'oak', 'graminales');
  foreach my $entry ( @list)
	{
    if (defined $d->{data}->{plants}->{$entry}){
		readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s",$entry), $d->{data}->{plants}->{$entry}->{index}->{value} );
		readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s_Category",$entry), $d->{data}->{plants}->{$entry}->{index}->{category} );
		readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s_InSeason",$entry), $d->{data}->{plants}->{$entry}->{"in_season"} );
		readingsBulkUpdate($hash, sprintf("Breezometer_PollenIndex_%s_DataAvailable",$entry), $d->{data}->{plants}->{$entry}->{"data_available"} );
		}
  }


		readingsEndUpdate($hash, 1);
    readingsSingleUpdate($hash,'state',"Initialized",0);

		return undef;
	} or do  {
		Log3 $name, 5, 'Failure decoding: ' . $@;
		return undef;
	}
}

sub Breezometer_RequestUpdateCurrentPollenData($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (not defined $hash){
		Log3 $name, 1, "Error on Breezometer_RequestUpdateCurrentPollenData. Missing hash variable";
		return undef;
	}

	Log3 $name, 4, "Breezometer_RequestUpdateCurrentPollenData Called for non-blocking value update. Name: $name";


		my $readTemplate = $Breezometer_url{"getCurrentPollenData"};

    my $longitude = InternalVal($name,'Longitude', undef);
		$readTemplate =~ s/#longitude#/$longitude/g;
		my $latitude = InternalVal($name,'Latitude', undef);
		$readTemplate =~ s/#latitude#/$latitude/g;
		my $apiKey = InternalVal($name,'API_Key', undef);
		$readTemplate =~ s/#apikey#/$apiKey/g;
    $readTemplate =~ s/#features#/types_information,plants_information/g;

		my $request = {
			url           => $readTemplate,
			header        => "Content-Type:application/json;charset=UTF-8",
			method        => 'GET',
			timeout       =>  2,
			hideurl       =>  1,
			callback      => \&Breezometer_UpdateCurrentPollenDataCallback,
			hash          => $hash
		};

		Log3 $name, 5, 'NonBlocking Request: ' . Dumper($request);

		HttpUtils_NonblockingGet($request);
    readingsSingleUpdate($hash,'state',"Request running",0);

		return undef;
}






1;

=pod
=begin html

<a name="Tado"></a>
<h3>Tado</h3>
<ul>
<i>Tado</i> implements an interface to the Tado cloud. The plugin can be used to read and write
temperature and settings from or to the Tado cloud. The communication is based on the reengineering of the protocol done by
Stephen C. Phillips. See <a href="http://blog.scphillips.com/posts/2017/01/the-tado-api-v2/">his blog</a> for more details.
Not all functions are implemented within this FHEM extension. By now the plugin is capable to
interact with the so called zones (rooms) and the registered devices. The devices cannot be
controlled directly. All interaction - like setting a temperature - must be done via the zone and not the device.
This means all configuration like the registration of new devices or the assignment of a device to a room
must be done using the Tado app or Tado website directly. Once the configuration is completed this plugin can
be used.
This device is the 'bridge device' like a HueBridge or a CUL. Per zone or device a dedicated device of type
'TadoDevice' will be created.
<br><br>
<a name="Tadodefine"></a>
<b>Define</b>
<ul>
<code>define &lt;name&gt; Tado &lt;username&gt; &lt;password&gt; &lt;interval&gt;</code>
<br><br>
Example: <code>define TadoBridge Tado mail@provider.com somepassword 120</code>
<br><br>
The username and password must match the username and password used on the Tado website.
Please be aware that username and password are stored and send as plain text. They are visible in FHEM user interface.
It is recommended to create a dedicated user account for the FHEM integration.
The Tado extension needs to pull the data from the Tado website. The 'Interval' value defines how often the value is refreshed.
</ul>
<br>
<b>Set</b><br>
<ul>
<code>set &lt;name&gt; &lt;option&gt;</code>
<br><br>
The <i>set</i> command just offers very limited options.
If can be used to control the refresh mechanism. The plugin only evaluates
the command. Any additional information is ignored.
<br><br>
Options:
<ul>
<li><i>interval</i><br>
Sets how often the values shall be refreshed.
This setting overwrites the value set during define.</li>
<li><i>start</i><br>
(Re)starts the automatic refresh.
Refresh is autostarted on define but can be stopped using stop command. Using the start command FHEM will start polling again.</li>
<li><i>stop</i><br>
Stops the automatic polling used to refresh all values.</li>
</ul>
</ul>
<br>
<a name="Tadoget"></a>
<b>Get</b><br>
<ul>
<code>get &lt;name&gt; &lt;option&gt;</code>
<br><br>
You can <i>get</i> the major information from the Tado cloud.
<br><br>
Options:
<ul>
<li><i>home</i><br>
Gets the home identifier from Tado cloud.
The home identifier is required for all further actions towards the Tado cloud.
Currently the FHEM extension only supports a single home. If you have more than one home only the first home is loaded.
<br/><b>This function is automatically executed once when a new Tado device is defined.</b></li>
<li><i>zones</i><br>
Every zone in the Tado cloud represents a room.
This command gets all zones defined for the current home.
Per zone a new FHEM device is created. The device can be used to display and
overwrite the current temperatures.
This command can always be executed to update the list of defined zones. It will not touch any existing
zone but add new zones added since last update.
<br/><b>This function is automatically executed once when a new Tado device is defined.</b></li>
</li>
<li><i>update</i><br/>
Updates the values of: <br/>
<ul>
<li>All Tado zones</li>
<li>All mobile devices - if attribute <i>generateMobileDevices</i> is set to true</li>
<li>The weather device - if attribute <i>generateWeather</i> is set to true</li>
</ul>
This command triggers a single update not a continuous refresh of the values.
</li>
<li><i>devices</i><br/>
Fetches all devices from Tado cloud and creates one TadoDevice instance
per fetched device. This command will only be executed if the attribute <i>generateDevices</i> is set to <i>yes</i>. If the attribute is set to <i>no</i> or not existing an error message will be displayed and no communication towards Tado will be done.
This command can always be executed to update the list of defined devices.
It will not touch existing devices but add new ones.
Devices will not be updated automatically as there are no values continuously changing.
</li>
<li><i>mobile_devices</i><br/>
Fetches all defined mobile devices from Tado cloud and creates one TadoDevice instance
per mobile device. This command will only be executed if the attribute <i>generateMobileDevices</i> is set to <i>yes</i>. If the attribute is set to <i>no</i> or not existing an error message will be displayed and no communication towards Tado will be done.
This command can always be executed to update the list of defined mobile devices.
It will not touch existing devices but add new ones.
</li>
<li><i>weather</i><br/>
Creates or updates an additional device for the data bridge containing the weather data provided by Tado. This command will only be executed if the attribute <i>generateWeather</i> is set to <i>yes</i>. If the attribute is set to <i>no</i> or not existing an error message will be displayed and no communication towards Tado will be done.
</li>
</ul>
</ul>
<br>
<a name="Tadoattr"></a>
<b>Attributes</b>
<ul>
<code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
<br><br>
You can change the behaviour of the Tado Device.
<br><br>
Attributes:
<ul>
<li><i>generateDevices</i><br>
By default the devices are not fetched and displayed in FHEM as they don't offer much functionality.
The functionality is handled by the zones not by the devices. But the devices offers an identification function <i>sayHi</i> to show a message on the specific display. If this function is required the Devices can be generated. Therefor the attribute <i>generateDevices</i> must be set to <i>yes</i>
<br/><b>If this attribute is set to <i>no</i> or if the attribute is not existing no devices will be generated..</b>
</li>
<li><i>generateMobileDevices</i><br>
By default the mobile devices are not fetched and displayed in FHEM as most users already have a person home recognition. If Tado shall be used to identify if a mobile device is at home this can be done using the mobile devices. In this case the mobile devices can be generated. Therefor the attribute <i>generateMobileDevices</i> must be set to <i>yes</i>
<br/><b>If this attribute is set to <i>no</i> or if the attribute is not existing no mobile devices will be generated..</b>
</li>
<li><i>generateWeather</i><br>
By default no weather channel is generated. If you want to use the weather as it is defined by the tado system for your specific environment you must set this attribute. If the attribute <i>generateWeather</i> is set to <i>yes</i> an additional weather channel can be generated.
<br/><b>If this attribute is set to <i>no</i> or if the attribute is not existing no Devices will be generated..</b>
</li>
</ul>
</ul>
</ul>

=end html

=cut
