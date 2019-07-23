*! version 1.3 7JUN2019  DIME Analytics dimeanalytics@worldbank.org

	capture program drop iecompdup
	program iecompdup , rclass

	qui {

		syntax varname ,  id(string) [DIDIfference KEEPDIFFerence KEEPOTHer(varlist) uniquevar(varname) uniquevals(string) more2ok]

		version 11.0

		preserve

/*******************************************************************************
	Test inputs and prepare data
*******************************************************************************/

			* Turn ID var to string so that the rest of the command works similarly
			stringid `varlist'
			
			* Only keep duplicates with the ID specified
			keep if  `varlist' == "`id'"

			* Test input on keepother() option
			if "`keepother'" != "" {
				testkeep, `keepdifference' keepother("`keepother'")
			}

			* Check number of duplicates
			count
			
			* If less then 2, there are no duplicates and it makes no sense to use the command 
			if `r(N)' == 2 next
			else if `r(N)' < 2  {
				testless `varlist', id("`id'") ndup(`r(N)')
			}
			* If more then 2, other options need to be specified so the command can compare observations
			else if `r(N)' > 2 {
			
				* Test that the options were correctly specified
				testmore varname, id("`id'") uniquevar("`uniquevar'") uniquevals("`uniquevals'") `more2ok'
				
				* If they were correctly specified, keep only the selected observations
				
				* more2ok keeps only the first two observations
				if "`more2ok'" != "" {
					keep if _n <= 2
				}
				* If the observations were explicitly selected
				else {
					
					* Test that the options were correctly specified
					testunique varname, id("`id'") uniquevar("`uniquevar'") uniquevals("`uniquevals'")
					
					* Keep the relevant observations
					keep if inlist(`uniquevar', `: word 1 of "`uniquevals'" ', `: word 2 of "`uniquevals'" ')
				}
			}
			
/*******************************************************************************
	Compare all variables
*******************************************************************************/

			*Initiate the locals
			local match
			local difference

			* Go over all variables and see if they are non missing for at least one of the variables
			foreach var of varlist _all {

				cap assert missing(`var')

				** If not missing for at lease one of the observations, test
				*  if they are identical across the duplicates or not, and
				*  store variable name in appropriate local
				if _rc {

					* Are the variables identical
					if `var'[1] == `var'[2] {
						local match `match' `var'
					}
					else {
						local difference `difference' `var'
					}
				}
				* If missing for all duplicates, then drop that variable
				else {
					drop `var'
				}
			}

			* Remove the ID var from the match list, it is match by definition and therefore add no information
			local match : list match - varlist

/*******************************************************************************
	Output the results
*******************************************************************************/

			noi di ""
			** Display all variables that differ. This comes first in case
			*  the number of variables are a lot, cause then it would push
			*  any other output to far up
			if "`didifference'" != "" {

				noi di "{phang}The following variables have different values across the duplicates:{p_end}"
				noi di "{pstd}`difference'{p_end}"
				noi di ""
			}

			*Display number output
			local numNonMissing = `:list sizeof match' + `:list sizeof difference'

			noi di "{phang}The duplicate observations with ID = `id' have non-missing values in `numNonMissing' variables. Out of those variables:{p_end}"
			noi di ""
			noi di "{phang2}`:list sizeof match' variable(s) are identical across the duplicates{p_end}"
			noi di "{phang2}`:list sizeof difference' variable(s) have different values across the duplicates{p_end}"



			return local matchvars 	`"`match'"'
			return local diffvars 	`"`difference'"'

			return scalar nummatch	= `:list sizeof match'
			return scalar numdiff 	= `:list sizeof difference'
			return scalar numnomiss	= `numNonMissing'

		restore

/*******************************************************************************
	If keep difference is applied, return only different or selected variables
*******************************************************************************/

		if "`keepdifference'" != "" & "`difference'" != "" {

			order `varlist' `difference' `keepother'
			keep `varlist' `difference' `keepother'

			* Drop differently depending on numeric or string
			cap confirm numeric variable `varlist'
			if !_rc {
				keep if  `varlist' == `id'
			}
			else {
				keep if  `varlist' == "`id'"
			}
		}
	}
	
	end

/*******************************************************************************

	Subprograms to test inputs and prepare data
	
*******************************************************************************/

*------------------------------------------------------------------------------*
*	Turn ID var to string so that the rest of the command works similarly
*------------------------------------------------------------------------------*

capture program drop stringid
		program 	 stringid

qui {
	
	syntax varname
		
	* Test if ID variable fully identifies the data (otherwise, the next test will not work)
	qui count if missing(`varlist')
	if r(N) != 0 {
		di as error "{phang}The ID variable contains missing values. The data set is not fully identified.{p_end}"
		error 459
		exit
	}
			
	* Test if ID variable is numeric or string
	cap confirm numeric variable `varlist'
	if !_rc {

		* If numeric, test if all values in ID variable is integer
		cap assert mod(`varlist',1) == 0

		* This command does not allow numeric ID variables that are not integers
		if _rc {
			di as error "{phang}The ID variable is only allowed to be either string or only consist of integers. Integer in this context is not the same as the variable type int. Integer in this context means numeric values without decimals. Please consider using integers as your ID or convert your ID variable to a string.{p_end}"

		}
		else {

			** Find the longest (for integers that is the same as largest)
			*  number and get its legth.l
			sum `varlist'
			local length 	= strlen("`r(max)'")

			** Use that length when explicitly setting the format in
			*  order to prevent information lost
			tostring `varlist', replace format(%`length'.0f) force
		}
	}

		* Testing that the ID variable is a string before continuing the command
		cap confirm string variable `varlist'
		if _rc {
			di as error "{phang}This error message is not due to incorrect specification from you. This message follows a failed check that the command is working properly. If you get this error, please send an email to kbjarkefur@worldbank.org including the follwoing message 'ID var was not succesfully turned in to a string without information loss in iecompdup.' and include whatever other data you do not mind sharing.{p_end}"
		}
}

end

*------------------------------------------------------------------------------*
*	Test input on "keep" options
*------------------------------------------------------------------------------*

capture program drop testkeep
		program		 testkeep
	
qui {

	syntax anything, [keepother(varlist) keepdifference]

	if "`keepdifference'" == "" & "`keepother'" != "" {

		noi di as error "{phang}Not allowed to specify option {inp:keepother()} without specifying {inp:keepdifference}.{p_end}"
		noi di ""
		error 197
		exit
	}
}

end

*------------------------------------------------------------------------------*
*	Test the number of duplicates 
*------------------------------------------------------------------------------*

capture program drop testless
		program		 testless

qui {

	syntax varname ,  id(string) ndup(integer)
		
	if `ndup' == 0 {

		noi di as error "{phang}ID incorrectly specified. No observations with (`varlist' == `id'){p_end}"
		noi di ""
		error 2000
		exit
	}
	else if `ndup' == 1 {

		noi di as error "{phang}ID incorrectly specified. No duplicates with that ID. Only one observation where (`varlist' == `id'){p_end}"
		noi di ""
		error 2001
		exit
	}
}		
		
end

*------------------------------------------------------------------------------*
*	Test input if more than two duplicates 
*------------------------------------------------------------------------------*

capture program drop testmore
		program		 testmore
	
qui {

	syntax varname, id("`id'") uniquevar(string) uniquevals(string) [more2ok]

	* The user must either choose which observations to keep, or aknowledge that only the first two will be kept	
	if  !(("`uniquevar'" == "" | "`uniquevals'" == "") | "`more2ok'" == "") {
			
		noi di as error "{phang}There are more than 2 observations with (`varlist' == `id'). The current version of iecompdup is not able to compare more than 2 duplicates at the time. (How to output the results for groups larger than 2 is non-obvious and suggestions on how to do that are appreciated.) {p_end}"
		noi di as error "{phang}Either use the options {inp:uniquevar()} and {inp:uniquevals()} together to explicitly selected the observations to be compared or specify option {inp:more2ok} and the comparison will be done between the first and the second occurrences of the value `id' in `varlist'.{p_end}"
		noi di ""
		error 197
		exit
	}
	* User cannot specify that the first two should be kept AND select two observations
	else if (("`uniquevar'" != "" | "`uniquevals'" != "") & "`more2ok'" != "") {
		noi di as error "{phang}Option {inp:more2ok} cannot be used with options {inp:uniquevar()} and {inp:uniquevals()}.{p_end}"
		noi di ""
		error 197
		exit
	}
	* uniquevar and uniquevals must be used together
	else if !("`uniquevar'" != "" & "`uniquevals'" != "") & "`more2ok'" == "" {
		noi di as error "{phang}Options {inp:uniquevar()} and {inp:uniquevals()} must be used together.{p_end}"
		noi di ""
		error 197
		exit
	}	
}
	
end
			
*------------------------------------------------------------------------------*
*	Test input duplicated observations to be compared were explicitly selected
*------------------------------------------------------------------------------*


capture program drop testunique
		program		 testunique, rclass
	
qui {

	syntax varname, id("`id'") uniquevar(string) uniquevals(string)

	*Test that the unique var fully and uniquely identifies the data set
	cap isid `uniquevar'
	if _rc {

		noi display as error "{phang}The variable {inp:`uniquevar'} listed in {inp:uniquevar()} does not uniquely and fully identify all observations in the data set.{p_end}"
		isid `uniquevar'
		error 198
		exit
	}
	
	** Test that the unique var is not in time format. Time values might be corrupted
	*  and changed a tiny bit when importing and exporting to Excel, which make merge not possible			
	local format : format `uniquevar'
	if substr("`format'",1,2) == "%t" {

		noi display as error `"{phang}The variable {inp:`uniquevar'} listed in {inp:uniquevar()} is using time format which is not allowed for consistency with {help:ieduplicates}. Stata and Excel store and display time slightly differently which can lead to small changes in the value when the value is imported and exported between Stata and Excel, and therefore the variable can no longer be used to merge the report back to the original data. Use another variable or create a string variable out of your time variable using this code: {inp: generate `uniquevar'_str = string(`uniquevar',"%tc")}.{p_end}"'
		noi di ""
		error 198
		exit
	}
	
	* Test that exactly 2 unique var values were selected
	local uniquevals 	= strtrim(`"`uniquevals'"')			// Remove trailing and leading spaces so we count the number of words correctly
	local n_uniquevals 	= wordcount(`"`uniquevals'"')		// Count how many IDs were specified
	
	if `n_uniquevals' > 2 {
		
		noi di as error "{phang}More than 2 values were listed in {inp:uniquevals()}. The current version of iecompdup is not able to compare more than 2 duplicates at the time. (How to output the results for groups larger than 2 is non-obvious and suggestions on how to do that are appreciated.) {p_end}"
		noi di ""
		error 198
		exit
	
	}
	if `n_uniquevals' < 2 {
		
		noi di as error "{phang}Less than 2 values were listed in {inp:uniquevals()}. For the command to run properly, specify 2 values taken by {inp:`uniquevar'} to compare.{p_end}"
		noi di ""
		error 198
		exit
	
	}
	
	return local uniquevals = `"`uniquevals'"'
}
	
end

	