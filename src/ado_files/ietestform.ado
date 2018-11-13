*! version 0.1 15DEC2017  DIME Analytics dimeanalytics@worldbank.org

capture program drop ietestform
		program ietestform , rclass

	syntax , surveyform(string) [csheetaliases(string) statalanguage(string)]


	/***********************************************
		Test the choice sheet inpependently
	***********************************************/
	importchoicesheet, form("`surveyform'") statalanguage(`statalanguage')

	*Get all choice lists actaually used
	local all_list_names `r(all_list_names)'


	/***********************************************
		Test the survey sheet inpependently
	***********************************************/
	importsurveysheet, form("`surveyform'") statalanguage(`statalanguage')

	*Get all choice lists actaually used
	local all_lists_used `r(all_lists_used)'


	/***********************************************
		Tests based on info from multiple sheets
	***********************************************/

	*Test that all lists in the choice sheet was actually used in the survey sheet
	local unused_lists : list all_list_names - all_lists_used
	if "`unused_lists'" != "" {
		noi di as error "{phang}There are lists in the choices sheets that are not used in any field in the survey sheet. These are the unused list(s): [{inp:`unused_lists'}].{p_end}"
		//error 688
		noi di ""
		noi di "end of error"
		noi di ""
	}

end

capture program drop importchoicesheet
		program 	 importchoicesheet , rclass
qui {
	//noi di "importchoicesheet command ok"
	syntax , form(string) [statalanguage(string)]
	//noi di "importchoicesheet syntax ok"

	*Gen the tempvars needed
	tempvar countmissing item_dup label_dup label_dup_all

	/***********************************************
		Load choices sheet from form
	***********************************************/

	*Import the choices sheet
	import excel "`form'", sheet("choices") clear first


	/***********************************************
		Get info from columns/variables and
		make tests on them
	***********************************************/

	*Create a list of all variables in the choice sheet
	ds
	local choicesheetvars `r(varlist)'

	*Test if old name "name" is used for value column
	if `:list posof "name" in choicesheetvars' ! = 0 {
		local valuevar "name"
	}
	*Test if new name "value" is used for value column
	else if `:list posof "value" in choicesheetvars' ! = 0 {
		local valuevar "value"
	}
	*Neither "name" or "value" is a name of a column, one must be used
	else {
		noi di as error "{phang}Either a column named [name] or a column named [value] is needed in the choice sheet.{p_end}"
		noi di ""
		//error 688
	}

	*Create a list of the variables with labels (multiple in case of multiple languages)
	foreach var of local choicesheetvars {
		if substr("`var'", 1, 5) == "label" local labelvars "`labelvars' `var'"
	}


	/***********************************************
		Get info from rowa/labels and
		make tests on them
	***********************************************/

	*Drop rows with all values missing
	egen `countmissing' = rownonmiss(_all), strok
	drop if `countmissing' == 0

	*Get a list with all the list names
	levelsof list_name, clean local("all_list_names")


	/***********************************************
		TEST - Numeric name
		Test that all variables in the name
		variable are numeric
	***********************************************/

	*Test if variable is numeric
	cap confirm numeric variable `valuevar'

	*Test if error code is 7, other codes should return other error message
	if _rc == 7 {

		*TODO: Find a way to list the non-numeric values identified

		noi di as error "{phang}There are non numeric values in the [`valuevar'] column in the choices sheet{p_end}"
		noi di ""
		//error 198
	}
	else if _rc != 0 {
		noi di as error "{phang}ERROR IN CODE LOGIC [cap confirm numeric variable `valuevar']{p_end}"
		noi di ""
		//error 198
	}


	/***********************************************
		TEST - No duplicates combinations
		Test that all combinations of
		list_name and name is unique
	***********************************************/

	*Test for duplicates and return error if not all combinations are unique
	duplicates tag list_name `valuevar', gen(`item_dup')
	count if `item_dup' != 0
	if `r(N)' > 0 {
		noi di as error "{phang}There are duplicates in the following list_names:{p_end}"
		noi list list_name `valuevar' if `item_dup' != 0
		noi di ""
		//error 198
	}


	/***********************************************
		TEST - No duplicates labels in list
		Test that there are no duplicate
		labels within a list
	***********************************************/

	*Local to indicate if error should be shown after all loops have completed
	local throw_label_dup_error 0

	*Initialize the dummy that indicate if there are duplicates to 0. This is used to store errors on
	gen `label_dup_all' = 0

	** Loop over each label language column
	foreach labelvar of local labelvars {

		*Reset vars and locals used in each label column
		replace `label_dup_all' = 0
		local lists_with_dups ""

		*Loop over each list name
		foreach list of local all_list_names {

			**Test for duplicates in the label var and display
			* errors if any observation do not have a unique,
			* i.e. `label_dup' != 0, label
			duplicates tag `labelvar' if list_name == "`list'", gen(`label_dup')

			*Was any duplicates found in this list
			count if `label_dup' == 1
			if `r(N)' > 0 {
				*Copy duplicate values to main
				replace `label_dup_all' = 1 if `label_dup' == 1

				local lists_with_dups =trim("`lists_with_dups' `list'")
			}

			*Drop the tempvar so that it can be generated again by duplicates
			drop `label_dup'
		}

		**If there are any duplicates in label within a list for this
		* label column, display error and list those cases
		count if `label_dup_all' == 1
		if `r(N)' > 0 {
			noi di as error "{phang}There are duplicate labels in the column `labelvar' within the [`lists_with_dups'] list(s) in the following labels:{p_end}"
			noi list list_name `valuevar' `labelvar' filter if `label_dup_all' == 1

			*Indicate that at least one error was thrown and that command should exit on error code.
			local throw_label_dup_error 1
		}
	}

	*Throw error code if at least one lable duplicate was found
	if `throw_label_dup_error' == 1 {
		noi di ""
		//error 141
	}


	/***********************************************
		TEST - Stata language for labels
		Test that there is one column with labels formatted for stata
	***********************************************/

	*User specified stata label name thar is not simply stata
	if "`statalanguage'" != "" {
		local labelstata "label`statalanguage'"
	}
	*Otherwise use the default name
	else {
		local labelstata "labelstata"
	}

	*Test if the Stata language
	if `:list labelstata in choicesheetvars' == 0 {

		*The user specified stata label language name does not exist. Throw error
		if "`statalanguage'" != "" {
			noi di as error "{phang}The label langauge specified in {inp:statalanguage(`statalanguage')} does not exist in the choice sheet. A column in the choice sheet must have a name that is [label:`statalanguage'].{p_end}"
			noi di ""
			//error 198
		}
		*The default stata label language name does not exist. Throw warning (error for now)
		else {
			noi di as error "{phang}There is no column in the choice sheet with the name [label:stata]. This is best practice as this allows you to automatically import choice list labels optimized for Stata's value labels making the data set easier to read.{p_end}"
			noi di ""
			//error 688
		}
	}


	/***********************************************
		Return values
	***********************************************/

	return local all_list_names				"`all_list_names'"

}
end

capture program drop importsurveysheet
		program 	 importsurveysheet , rclass
qui {
	syntax , form(string) [statalanguage(string)]


	*Gen the tempvars needed
	tempvar countmissing

	/***********************************************
		Load choices sheet from file and
		delete empty row
	***********************************************/

	*Import the choices sheet
	import excel "`form'", sheet("survey") clear first

	*Gen
	gen _excel_row_number = _n
	order _excel_row_number

	*Drop rows with all values missing
	egen `countmissing' = rownonmiss(_all), strok
	drop if `countmissing' == 0


	/***********************************************
		Get list of variables, do tests on them,
		and creates locals to be used below
	***********************************************/

	*Create a list of all variables in the choice sheet
	ds
	local surveysheetvars `r(varlist)'

	*Create a list of the variables with labels (multiple in case of multiple languages)
	foreach var of local choicesheetvars {
		if substr("`var'", 1, 5) == "label" local labelvars "`labelvars' `var'"
	}

	*Variables that must be included every time
	local name_vars 		"name"
	local cmd_vars  		"type required readonly appearance"
	local msg_vars  		"`labelvars' hint constraintmessage requiredmessage"
	local code_vars 		"default constraint  relevance  calculation repeat_count choice_filter"

	local surveysheetvars_required "`name_vars' `cmd_vars' `msg_vars' `code_vars'"

	*Test that all required vars are actually in the survey sheets
	if `: list surveysheetvars_required in surveysheetvars' == 0 {

		*Generate a list of the vars missing and display error
		local missing_vars : list surveysheetvars_required - surveysheetvars
		noi di as error "{phang}One or several variables required to run all the tests in this command are missing in this form. The following variable(s) are missing [`missing_vars'].{p_end}"
		noi di ""
		//error 688
	}

	keep `surveysheetvars_required' _excel_row_number

	*********
	*make command vars that sometimes are not used and then loaded as numeric
	foreach var of local cmd_vars  {

		tostring `var', replace
		replace `var' = lower(itrim(trim(`var')))
		replace `var' = "" if `var' == "."
	}



	/***********************************************
		Test type column
	***********************************************/

	noi test_survey_type

	return local all_lists_used				"`r(all_lists_used)'"


	noi test_survey_name

}
end

capture program drop test_survey_type
		program 	 test_survey_type , rclass
qui {


	noi di "test_survey_type command ok"
	//syntax , string(string) - No syntax needed at this point but likely to come later
	noi di "test_survey_type syntax ok"

	/***********************************************
		Standardizing name of type values
	***********************************************/

	replace type = "begin_group" 	if type == "begin group"
	replace type = "begin_repeat" 	if type == "begin repeat"
	replace type = "end_group" 		if type == "end group"
	replace type = "end_repeat" 	if type == "end repeat"

	replace type = "text_audit" 	if type == "text audit"
	replace type = "audio_audit" 	if type == "audio audit"


	/***********************************************
		Test end and begin
	***********************************************/

	*********
	*Short hand for begin_ or end_
	gen typeBegin 		= (type == "begin_group" 	| type == "begin_repeat")
	gen typeEnd 		= (type == "end_group" 		| type == "end_repeat")

	gen typeBeginEnd 	= (typeBegin | typeEnd)

	local begin_end_error = 0

	*Loop over all rows to test if begin and end match perfectly and give helpful error if not
	local num_rows = _N
	forvalues row = 1/`num_rows' {

		*This only applies to rows that end or begin a group or a repeat
		if typeBeginEnd[`row'] == 1 {

			* Get type and name for this row
			local row_type = type[`row']
			local row_name = name[`row']
			local isBegin = typeBegin[`row']


			* Test if any end_repeat or end_group has no name (begin are tested by server). This is not incorrect, but bad practice as it makes bug finding much more difficult.
			if "`row_name'" == "" {

				noi di as error "{phang}It is bad practice to leave the name column empty for end_group or end_repeat fields. While it is allowed in ODK it makes error finding harder and slower.{p_end}"
				noi list _excel_row_number type name if _n == `row'
				noi di ""
				//error 688
			}

			*Add begin group to stack if either begin_group or begin_repeat
			if `isBegin' {

				local type_and_name "`row_type'#`row_name' `type_and_name'"

			}

			*If end_group or end_repeat, test that the corresponding group or repeat group was the most recent begin, otherwise throw an error.
			else {

				*Get the type and name of the end_group or end_repeat of this row
				local endtype = substr("`row_type'", 5,6) //Remove the "end_" part of the type
				local endname = "`row_name'"

				*Get the type and name of the most recent begin_group or begin_repeat
				local lastbegin : word 1 of `type_and_name'			//the most recent is the first in the list

				*Get the begin type
				local begintype = substr("`lastbegin'", 7,6)		//Remove the "begin_" part of the type
				local begintype = subinstr("`begintype'","#","", .)	//Remove the # from "group" as it is one char shorter then "repeat"

				*Get the begin name
				local beginname = substr("`lastbegin'", strpos("`lastbegin'","#")+ 1,.) //Everything that follows the #

				//noi di "begintype `begintype'"
				//noi di "beginname `beginname'"

				//noi di "endtype `row_type'"
				//noi di "endname `endname'"

				*If the name are not the same it is most likely a different group or repeat group that is incorrectly being closed
				if "`endname'" != "`beginname'"  {

					noi di as error "{phang}The [{inp:end_`endtype' `endname'}] was found before [{inp:end_`begintype' `beginname'}]. No other than the most recent begin_group or begin_repeat can be ended. Either this is a typo in the names [{inp:`endname'}] and [{inp:`beginname'}], the [{inp:begin_`endtype' `endname'}] or the [{inp:end_`begintype' `beginname'}] are missing or the order of the begin and end of [{inp:`endname'}] and [{inp:`beginname'}] is incorrect.{p_end}"
					noi di ""
					local begin_end_error = 1 //Read all rows before throwing error code
				}

				* If name are the same but types are differnt, then it is most likely a typo in type
				else if "`endtype'" != "`begintype'" {

					noi di as error "{phang}The `begintype' [{inp:`endname'}] is ended with a [{inp:end_`begintype'}] which is not correct, a begin_`begintype' cannot be closed with a end_`begintype', not a end_`endtype'.{p_end}"
					noi di ""
					local begin_end_error = 1 //Read all rows before throwing error code
				}

				*Name and type are the same, this is a correct ending of the group or repeat group
				else {
					* The begin_group or begin_repeat is no longer the most recent, so remove it from the string
					local type_and_name = trim(substr("`type_and_name'", strlen("`lastbegin'")+1, .))
				}
			}
		}
	}

	*Throw error code if any errors were encountered above
	if `begin_end_error' {
		noi di ""
		//error 688
	}




	/***********************************************
		Parse select_one, select_multiple values
	***********************************************/

	*********
	*seperate choices lists from the select_one or select_many word
	split type, gen(type)
	*Makse sure that 3 variables were created even if not
	forvalues i = 1/3 {
		cap gen type`i' = ""
	}

	*Order new vars after original var, drop original var, and then give them descriptive nams
	order type?, after(type)
	drop type
	rename type1 type				//This stores field type, i.e. text, number, select_one, calculate, begin_group etc.
	rename type2 choiceList			//If select_one or select_multiple this stores the choice list used
	rename type3 choiceListOther	//If built in other option is used, it ends up here

	*Get a list with all the list names
	levelsof choiceList, clean local("all_lists_used")

	/***********************************************
		Return values
	***********************************************/

	return local all_lists_used				"`all_lists_used'"
}
end

capture program drop test_survey_name
		program 	 test_survey_name , rclass
qui {

	noi di "test_survey_name command ok"

	/***********************************************
		Gen value needed in tests
	***********************************************/

	gen namelen = strlen(name)
	order namelen, after(name) //jsut to make dev easier

	gen will_be_feild = !((inlist(type, "start", "end" )) | (typeBeginEnd == 1))

	/***********************************************
		Create vars that require going over
		all loops
	***********************************************/

	gen num_nested_repeats = 0

	*Loop over all rows
	local num_rows = _N

	forvalues row = 1/`num_rows' {

		if `row' > 1 {

			local lastrow = `row' -1

			if type[`row'] == "begin_repeat" {
				replace num_nested_repeats = num_nested_repeats[`lastrow'] + 1 if _n == `row'
			}
			else if type[`row'] == "end_repeat" {
				replace num_nested_repeats = num_nested_repeats[`lastrow'] - 1 if _n == `row'
			}
			else {
				replace num_nested_repeats = num_nested_repeats[`lastrow'] if _n == `row'
			}
		}
	}

	/***********************************************
		Test for long names
	***********************************************/

	gen namelen_repeat1 = namelen + num_nested_repeats * 2 //Adding "_1" for each loop
	gen namelen_repeat2 = namelen + num_nested_repeats * 3 //Adding "_10" for each loop

	*Names that are always too long
	gen longname	= (namelen > 32)
	gen longname1	= (namelen_repeat1 > 32)
	gen longname2	= (namelen_repeat2 > 32)

	cap assert longname == 0
	if _rc {
		noi di as error "{phang}These variable names are longer then 32 characters. That is allowed in the data formats used in SurveyCTO - and is therefore allowed in their test - but will cause an error when the data is imported to Stata. The following names should be shortened:{p_end}"
		noi list _excel_row_number type name if longname == 1
		noi di ""
		//error 198
	}

	cap assert longname1 == 0
	if _rc {
		noi di as error "{phang}These variable are inside one or several repeat groups. When this data is imported to Stata it will add {it:_x} to the variable name for each repeat group this variable is in, where {it:x} is the repeat count for that repeat. This test assumed that the repeat count is less than 9 so that only two characters ({it:_x}) are needed. The following varaibles are are longer then 32 characters if two characters will be adeed per repeat group and should therefore be shortened:{p_end}"
		noi list _excel_row_number type name num_nested_repeats if longname1 == 1
		noi di ""
		//error 198
	}

	cap assert longname2 == 0
	if _rc {
		noi di as error "{phang}These variable are inside one or several repeat groups. When this data is imported to Stata it will add {it:_xx} to the variable name for each repeat group this variable is in, where {it:xx} is the repeat count for that repeat. This test assumed that the repeat count is between 10 and 99 so that up to three characters ({it:_xx}) are needed. The following variables are are longer then 32 characters if two characters will be added per repeat group and should therefore be shortened:{p_end}"
		noi list _excel_row_number type name num_nested_repeats if longname2 == 1
		noi di ""
		//error 198
	}

}
end

pause on
ietestform , surveyform("C:\Users\kbrkb\Dropbox\work\CTO_HHMidline_v2.xls")
