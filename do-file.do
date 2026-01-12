*** #1 CLEANING AND PROCESSING THE CONSENSUS DATA

// Import data
clear
import delimited using "consensus.csv", varnames(1)

// Encode strings
encode country, gen(country_id)
destring year, replace

//Code p.targets
bysort country sector year target: egen target_covered = max(covered)
bysort country sector year target: gen tag_target = (_n == 1)
bysort country sector year: egen n_targets_covered = total(tag_target * (target_covered == 1))
gen n_targets_total = .
replace n_targets_total = 19 if sector == "Social"
replace n_targets_total = 48 if sector == "Environmental"
gen p_targets = n_targets_covered / n_targets_total
drop n_targets_covered n_targets_total tag_target

//Code Instrument Preponderance
bysort country sector year target: egen instr_prep = total(covered == 1)

// Code portfolio coverage: absolute number of covered target–instrument cells
preserve
    collapse(sum) covered (mean) p_targets (mean) instr_prep, by(sector country year country_id)
    rename covered portfolio_coverage
    rename p_targets mean_p_targets
    rename instr_prep mean_instr_prep
	
// Generate portfolio_space by sector (for size calculation)
gen portfolio_space = .
replace portfolio_space = 624 if sector == "Environmental"
replace portfolio_space = 114 if sector == "Social"

// Generate portfolio size
gen portfolio_size = portfolio_coverage / portfolio_space

// Define panel
egen panel_id = group(country_id sector)
xtset panel_id year

//Descriptive statistics
	*Correlation
	corr portfolio_size p_targets
	by sector, sort: corr portfolio_size p_targets
	
	*Variation correlation
	bysort country sector (year): gen d_portfolio    = portfolio_size - portfolio_size[_n-1]
	bysort country sector (year): gen d_ptarget = p_targets - p_targets[_n-1]
	corr d_size d_ptarget
	by sector, sort: corr d_portfolio d_ptarget

*** #2 CALCULATING DISMANTLING

// Calculate y-t-y change in portfolio size
bysort country_id sector (year): gen d_portfolio = portfolio_size - portfolio_size[_n-1]

// Keep only negative changes as intensity of dismantling
gen dismantling_intensity = d_portfolio
replace dismantling_intensity = 0 if missing(d_portfolio) | d_portfolio > 0

// Flag dismantling episodes (any net contraction)
gen dismantling_episode = d_portfolio < 0 if !missing(d_portfolio)

	* (Optional) identify major dismantling threshold
	gen major_dismantle = 0 if !missing(d_portfolio)
	replace major_dismantle = 1 if sector == "Social" & d_portfolio < -0.01
	replace major_dismantle = 1 if sector == "Environmental" & d_portfolio < -0.003

//Generate variation in mean p.target and mean instrument preponderance
bysort country_id sector (year): gen d_ptarget = mean_p_targets - mean_p_targets[_n-1]
bysort country_id sector (year): gen d_instrprep = mean_instr_prep - mean_instr_prep[_n-1]	
	
// Visualizing the data

	*All dismantling episodes
	list country_id sector year portfolio_size d_portfolio d_ptarget d_instrprep if dismantling_episode == 1, sepby(country_id sector)
	
	*Major dismantling episodes
	 list country_id sector year portfolio_size d_portfolio d_ptarget d_instrprep if major_dismantle ==1 , sepby(country_id sector)
	 
// Printing the dismantling episodes

	*Dismantling in general
preserve
keep if d_portfolio < 0
keep country sector year portfolio_size d_portfolio
sort country sector year

putdocx begin
putdocx table t1 = data(country sector year portfolio_size d_portfolio), varnames
putdocx save "dismantling_episodes.docx", replace
restore

	*Major dismantle
preserve
keep if d_portfolio < -0.01
keep country sector year portfolio_size d_portfolio
sort country sector year

putdocx begin
putdocx table t1 = data(country sector year portfolio_size d_portfolio), varnames
putdocx save "major_dismantling_episodes.docx", replace
restore


//Save as temporal file
tempfile panel
save `panel', replace



*** #3 ADDING CONTROL VARIABLES

// Import WDI data
clear
import delimited using "wdi_extract.csv", varnames(1)
replace countryname = "South Korea" if countryname == "Korea, Rep."
replace countryname = "Turkey"      if countryname == "Turkiye"

// Reshape from wide  to long
reshape long yr, i(countryname seriescode) j(year)
rename yr value

// Create separate variables for each series
replace seriescode = subinstr(seriescode, ".", "_", .)
drop seriesname
reshape wide value, i(countryname year) j(seriescode) string
rename (valueGE_EST valueNY_GDP_PCAP_KD valueNY_GDP_MKTP_KD_ZG valueNE_TRD_GNFS_ZS)(gov_eff gdp_pc gdp_g trade)
destring gov_eff trade gdp_g gdp_pc, replace ignore(`".."', illegal)
collapse gov_eff gdp_pc gdp_g trade, by (countryname year)
rename countryname country
save "wdi_reshaped.dta", replace

// Merge with panel
use `panel', clear
merge m:1 country year using "wdi_reshaped.dta"
drop _merge
save "panel_wdi.dta", replace

// Import PolCon data
clear
import delimited using "polcon_clean.csv", varnames(1)
rename politycountry country

//Germany value fix and Korea name standarization
replace country = "South Korea" if country == "Korea, South"
drop if country == "Germany East"
replace country = "Germany" if country == "Germany West"
collapse (mean) polconiii, by(country year executiveparty executivepartydom primeministername)

//Save clean polcon
drop if missing(country)
drop if missing(year)
save "polcon_clean.dta", replace

// Merge with full panel 
use "panel_wdi.dta", clear
drop if missing(country_id)
merge m:1 country year using "polcon_clean.dta"
drop if _merge == 2
drop _merge
compress executivepartydom
save "panel_polcon.dta", replace


*** THIS SECTION NEEDS REWORKING, AS THERE IS NO EXACT MATCH BETWEEN PARTY NAMES***
// Merge with V-Party data
//Prepare V-Party
use "V-Dem-CPD-Party-V2.dta", clear
rename country_name country
rename v2paenname executivepartydom
keep country year executivepartydom v2xpa_popul

// Fix for the duplicates in Zimbabwe, Chile and North Macedonia, which are irrelevant for the analysis
duplicates tag country year executivepartydom, gen(dup) 
drop if dup == 1
drop dup
save "VParty.dta", replace

preserve
    use "panel_polcon.dta", clear
    keep country year executivepartydom
    duplicates drop
    tempfile exec_party_year
    save `exec_party_year'
restore

preserve
    use `exec_party_year', clear
	compress executivepartydom
    merge m:1 country year executivepartydom using "VParty.dta"
    keep if _merge == 1 | _merge == 3
    drop _merge
    tempfile exec_party_year_popul
    save `exec_party_year_popul'
restore

use "panel_polcon.dta", clear
merge m:1 country year executivepartydom using `exec_party_year_popul'
keep if _merge == 1 | _merge == 3
drop _merge
save "final_panel.dta", replace

*********

*** #4/Optional FIX FOR GOV EFF DATA //Just in case, in my case the original export was faulty
clear
import delimited using "wdi_goveff.csv", varnames(1)
replace countryname = "South Korea" if countryname == "Korea, Rep."
replace countryname = "Turkey" if countryname == "Turkiye"

// Reshape from wide  to long
destring yr1976-yr2005, replace ignore("..")
reshape long yr, i(countryname) j(year)
rename yr value

// Create separate variables for each series
drop seriesname seriescode
collapse value, by (countryname)
rename countryname country
rename value gov_eff_mean
save "wdi_goveff_reshaped.dta", replace

//Final (hopefully) merge
use "final_panel.dta"
merge m:1 country using "wdi_goveff_reshaped.dta"
drop if _merge == 2
drop _merge
save "final_panel.dta", replace

//Print gov effectiveness means
gsort -gov_eff_mean
putdocx begin
putdocx table t1 = data(country gov_eff_mean), varnames
putdocx save "gov_eff_means.docx", replace

*** #4 FINAL ANALYSIS

use "final_panel.dta", clear
encode sector, gen(sector_id)

//Define control variables
gen log_gdppc = log(gdp_pc)
gen log_gdpg = log(gdp_g)

//Center year
gen year_c = year - 1976

// Standarize continuous variables following Adam et al (2017)
foreach var in gov_eff_mean log_gdppc log_gdpg trade polconiii year_c {
    summarize `var' if !missing(`var')
    gen z_`var' = (`var' - r(mean)) / (2*r(sd))
}

xtset panel_id year

//Multilevel mixed effects logit
melogit dismantling_episode z_gov_eff_mean z_log_gdppc z_log_gdpg z_trade z_polconiii z_year_c i.sector_id || country:

melogit dismantling_episode z_gov_eff_mean z_log_gdppc z_log_gdpg z_trade z_polconiii z_year_c|| country: || sector_id:

melogit dismantling_episode gov_eff_mean log_gdppc log_gdpg trade polconiii year_c i.sector_id || country:

//Simple logit
logit dismantling_episode gov_eff_mean log_gdppc log_gdpg trade polconiii

// Simple logit with clustered errors
logit dismantling_episode gov_eff_mean log_gdppc log_gdpg trade polconiii year_c i.sector_id, vce(cluster country)

