*! version 0.1 12DEC2018  DIME Analytics dimeanalytics@worldbank.org

capture program drop ietestform
		program ietestform , rclass

qui {

	version 13

	preserve
		
	syntax , surveyform(string) report(string) [statalanguage(string)]
	
	
	/***********************************************
		Test input
	***********************************************/
	
	*Test that the form file exists
	cap confirm file "`surveyform'"
	if _rc {
		
		noi di as error "{phang}The SCTO questionnaire form file in surveyform(`surveyform') was not found.{p_end}"
		error _rc
	}
	
	*TODO: add test for form file is xls or xsls
	*TODO: add test for report file
		* folder exists
		* file type is cvs or file type where we will add csv to name
	
	/***********************************************
		Get form meta data and set up report file
	***********************************************/
	
	*Get meta data on the form from the form setting sheet
	importsettingsheet, form("`surveyform'")
	
	*Load returned values in locals
	local meta_v		= "`r(version)'" 
    local meta_id		= "`r(form_id)'" 
    local meta_title	= "`r(form_title)'"
	
	*Setup the report tempfile where all results from all tests will be written
	tempfile report_tempfile
	noi report_file setup , report_tempfile("`report_tempfile'") ///
		metav("`meta_v'") metaid("`meta_id'") metatitle("`meta_title'") metafile("`surveyform'")
	

	/***********************************************
		Test the choice sheet independently
	***********************************************/
	
	noi importchoicesheet, form("`surveyform'") statalanguage(`statalanguage') report_tempfile("`report_tempfile'")

	*Get all choice lists actaually used
	local all_list_names `r(all_list_names)'


	/***********************************************
		Test the survey sheet independently
	***********************************************/
	
	noi importsurveysheet, form("`surveyform'") statalanguage(`statalanguage') report_tempfile("`report_tempfile'")

	*Get all choice lists actaually used
	local all_lists_used `r(all_lists_used)'


	/***********************************************
		Tests based on info from multiple sheets
	***********************************************/

	/***********************************************
		TEST - No unused lists
		Test that all lists in the choice sheet were
		actually used in the survey sheet
	***********************************************/
	local unused_lists : list all_list_names - all_lists_used
	if "`unused_lists'" != "" {

		local error_msg "There are lists in the choice sheet that are not used by any field of the survey sheet. These are the unused list(s): [`unused_lists']"
		report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Unused_Choice_Lists")
	}

	/***********************************************
		Finsish the report and write it to disk
	***********************************************/	
	
	*Write the file to disk
	noi report_file write, report_tempfile("`report_tempfile'") filepath("`report'")
	
	restore
	
}
end

** This program imports the settings sheet and get meta information to be used in report header
capture program drop importsettingsheet
		program 	 importsettingsheet , rclass
		
qui {

	//noi di "importsettingsheet command ok"
	syntax , form(string) 
	//noi di "importsettingsheet syntax ok"
	
	*Import the choices sheet
	import excel "`form'", sheet("settings") clear first
	
	if _rc == 603 {
		noi di as error  "{phang}The file `form' cannot be opened. This error can occur for two reasons: either you have this file open, or it is saved in a version of Excel that is more recent than the version of Stata. If the file is not opened, try saving your file in an version of Excel.{p_end}"
		error 603
	}
	else if _rc {
		import excel "`form'", sheet("settings") clear first
	}

	*Return the settings in return locals
	return local form_title = form_title[1]
	return local form_id 	= form_id[1]
	return local version 	= version[1]

} 
end


** This program imports the choice sheet and run tests on the information there
capture program drop importchoicesheet
		program 	 importchoicesheet , rclass
		
qui {
	//noi di "importchoicesheet command ok"
	syntax , form(string) [statalanguage(string) report_tempfile(string)]
	//noi di "importchoicesheet syntax ok"

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
		error 688
	}

	*Create a list of the variables with labels (multiple in case of multiple languages)
	foreach var of local choicesheetvars {
		if substr("`var'", 1, 5) == "label" local labelvars "`labelvars' `var'"
	}


	/***********************************************
		Get info from rows/labels and
		make tests on them
	***********************************************/

	*Drop rows with all values missing
	egen 	countmissing = rownonmiss(_all), strok
	drop if countmissing == 0

	*Get a list with all the list names
	levelsof list_name, clean local("all_list_names")

	*Count number of non-missing
	egen 	labelmiss	 = rowmiss(`labelvars')
	egen 	labelnonmiss = rownonmiss(`labelvars'), strok

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

		local error_msg "There are non numeric values in the [`valuevar'] column of the choice sheet"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'")
			wikifragment("Value.2FName_Numeric")

	}
	else if _rc != 0 {
		noi di as error "{phang}ERROR IN CODE LOGIC [cap confirm numeric variable `valuevar']{p_end}"
		noi di ""
		error 198
	}


	/***********************************************
		TEST - No duplicates combinations
		Test that all combinations of
		list_name and name is unique
	***********************************************/

	*Test for duplicates and return error if not all combinations are unique
	duplicates tag list_name `valuevar', gen(list_item_dup)

	replace list_item_dup = 0 if missing(`valuevar')	//If value var is missing, it is not a duplicate, it will be tested for later.

	count if list_item_dup != 0
	if `r(N)' > 0 {

		local error_msg "There are duplicates in the following list_names:"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Duplicated_List_Code") table("list list_name `valuevar' if list_item_dup != 0")
	}

	/***********************************************
		TEST - Value labels with no values
		Test that all non-missing values in the label
		column have a name/value
	***********************************************/

	*Test for duplicates and return error if not all combinations are unique
	gen lable_with_missvalue = (missing(`valuevar') & labelnonmiss != 0)
	count if lable_with_missvalue != 0
	if `r(N)' > 0 {

		local error_msg "There non-missing values in the [label] column of the choice sheet for rows that have missing value in the [`valuevar'] column:"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Missing_Labels_or_Value.2FName_in_Choice_Lists") table("list list_name `valuevar' `labelvars' if lable_with_missvalue != 0")
	}

	/***********************************************
		TEST - Unlabelled values
		Test that all values/names have a label
	***********************************************/

	*Test for duplicates and return error if not all combinations are unique
	gen unlabelled = (!missing(`valuevar') & labelnonmiss == 0)
	count if unlabelled != 0
	if `r(N)' > 0 {

		local error_msg "There non-missing values in the [`valuevar'] column of the choice sheet without a label in the [label] colum:"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Missing_Labels_or_Value.2FName_in_Choice_Lists") table("list list_name `valuevar' `labelvars' if unlabelled != 0")
	}

	/***********************************************
		TEST - No duplicates labels in list
		Test that there are no duplicate
		labels within a list
	***********************************************/

	*Initialize the dummy that indicate if there are duplicates to 0. This is used to store errors on
	gen label_all_cols_dup = 0

	** Loop over each label language column
	foreach labelvar of local labelvars {

		*Reset vars and locals used in each label column
		replace label_all_cols_dup = 0
		local lists_with_dups ""

		*Loop over each list name
		foreach list of local all_list_names {

			**Test for duplicates in the label var and display
			* errors if any observation do not have a unique,
			* i.e. label_dup != 0, label
			duplicates tag `labelvar' if list_name == "`list'", gen(label_dup)

			*Was any duplicates found in this list
			count if label_dup == 1
			if `r(N)' > 0 {
				*Copy duplicate values to main
				replace label_all_cols_dup = 1 if label_dup == 1

				local lists_with_dups =trim("`lists_with_dups' `list'")
			}

			*Drop the tempvar so that it can be generated again by duplicates
			drop label_dup
		}

		**If there are any duplicates in label within a list for this
		* label column, display error and list those cases
		count if label_all_cols_dup == 1
		if `r(N)' > 0 {

			local error_msg "There are duplicated entries in the [`labelvar'] column of the choice sheet within the [`lists_with_dups'] list(s) for the following labels:"

			noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Duplicated_List_Labels") table("list list_name `valuevar' `labelvar' filter if label_all_cols_dup == 1")

		}
	}


	/***********************************************
		TEST - Stata language for value labels
		Test that there is one column with labels formatted for stata
	***********************************************/

	*User specified stata label name that is not simply stata
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
			noi di as error "{phang}The label language specified in {inp:statalanguage(`statalanguage')} does not exist in the choice sheet. A column in the choice sheet must have a name that is [label:`statalanguage'].{p_end}"
			noi di ""
			error 198
		}
		*The default stata label language name does not exist. Throw warning (error for now)
		else {

			local error_msg "There is no column in the choice sheet with the name [label:stata]. This is best practice as it allows you to automatically import choice list labels optimized for Stata's value labels, making the data set easier to read."

			noi report_file add , report_tempfile("`report_tempfile'") wikifragment("Stata_Labels_Columns") message("`error_msg'")

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
	syntax , form(string) [statalanguage(string) report_tempfile(string)]

	*Gen the tempvars needed
	tempvar countmissing

	/***********************************************
		Load choices sheet from file and
		delete empty row
	***********************************************/

	*Import the choices sheet
	import excel "`form'", sheet("survey") clear first

	*Gen
	gen row = _n
	order row

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
	foreach var of local surveysheetvars {
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
		error 688
	}

	keep `surveysheetvars_required' row

	*********
	*make command vars that sometimes are not used and then loaded as numeric
	foreach var of local cmd_vars  {

		tostring `var', replace
		replace `var' = lower(itrim(trim(`var')))
		replace `var' = "" if `var' == "."
	}


	/***********************************************
		TEST - Type column
		Test for not matching begin/end group/repeat
	***********************************************/

	*Do tests related to the type column
	noi test_survey_type, report_tempfile("`report_tempfile'")

	*Ruturn the list of used choice lists to be compared with list of all lists
	return local all_lists_used				"`r(all_lists_used)'"

	/***********************************************
		Test name column
	***********************************************/

	noi test_survey_name, report_tempfile("`report_tempfile'")

	/***********************************************
		Test label column
	***********************************************/

	noi test_survey_label, surveysheetvars(`surveysheetvars_required') statalanguage(`statalanguage') report_tempfile("`report_tempfile'")

}
end

capture program drop test_survey_type
		program 	 test_survey_type , rclass
qui {

	//noi di "test_survey_type command ok"
	syntax ,  [report_tempfile(string)]
	//noi di "test_survey_type syntax ok"

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

				local error_msg "It is bad practice to leave the name column empty for end_group or end_repeat fields. While this is allowed in ODK, it makes error finding harder and slower. The following repeat or end groups have empty name columns:"

				noi report_file add , report_tempfile("`report_tempfile'") wikifragment("Matching_begin_.2Fend") message("`error_msg'") table("list row type name if _n == `row'")
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

				*If the name are not the same it is most likely a different group or repeat group that is incorrectly being closed
				if "`endname'" != "`beginname'"  {

					local error_msg "The [end_`endtype' `endname'] was found before [end_`begintype' `beginname']. No other than the most recent begin_group or begin_repeat can be ended. Either this is a typo in the names [`endname'] and [`beginname'], the [begin_`endtype' `endname'] or the [end_`begintype' `beginname'] are missing or the order of the begin and end of [`endname'] and [`beginname'] is incorrect."

					noi report_file add ,  report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Matching_begin_.2Fend")

				}

				* If name are the same but types are differnt, then it is most likely a typo in type
				else if "`endtype'" != "`begintype'" {

					local error_msg "The `begintype' [`endname'] is ended with a [end_`begintype'] which is not correct, a begin_`begintype' cannot be closed with a end_`begintype', not a end_`endtype'."

					noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Matching_begin_.2Fend")

				}

				*Name and type are the same, this is a correct ending of the group or repeat group
				else {
					* The begin_group or begin_repeat is no longer the most recent, so remove it from the string
					local type_and_name = trim(substr("`type_and_name'", strlen("`lastbegin'")+1, .))
				}
			}
		}
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

	//noi di "test_survey_name command ok"
	syntax ,  [report_tempfile(string)]
	//noi di "test_survey_name syntax ok"

	/***********************************************
		Gen value needed in tests
	***********************************************/

	gen namelen = strlen(name)
	order namelen, after(name) //jsut to make dev easier

	gen will_be_field = !((inlist(type, "start", "end" )) | (typeBeginEnd == 1))

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
		TEST - Long variable names
	***********************************************/

	gen namelen_repeat1 = namelen + num_nested_repeats * 2 //Adding "_1" for each loop
	gen namelen_repeat2 = namelen + num_nested_repeats * 3 //Adding "_10" for each loop

	*Names that are always too long
	gen longname    = (namelen > 32)
    gen longname1   = (namelen_repeat1 > 32 & longname 	== 0) 	//if longname is 1, then this test is redundant
    gen longname2   = (namelen_repeat2 > 32 & longname1 == 0) 	//if longname1 is 1, then this test is redundant

	cap assert longname == 0
	if _rc {

		local error_msg "These variable names are longer then 32 characters. That is allowed in the data formats used in SurveyCTO - and is therefore allowed in their test - but will cause an error when the data is imported to Stata. The following names should be shortened:"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Field_Name_Length") able("list row type name if longname == 1")

	}

	cap assert longname1 == 0
	if _rc {

		local error_msg "These variable are inside one or several repeat groups. When this data is imported to Stata it will add {it:_x} to the variable name for each repeat group this variable is in, where {it:x} is the repeat count for that repeat. This test assumed that the repeat count is less than 9 so that only two characters ({it:_x}) are needed. The following variables's name will be longer then 32 characters if two characters are added per repeat group and should therefore be shortened:"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Repeat_Group_Field_Name_Length") table("list row type name num_nested_repeats if longname1 == 1")

	}

	cap assert longname2 == 0
	if _rc {

		local error_msg "These variable are inside one or several repeat groups. When this data is imported to Stata it will add {it:_xx} to the variable name for each repeat group this variable is in, where {it:xx} is the repeat count for that repeat. This test assumed that the repeat count is between 10 and 99 so that up to three characters ({it:_xx}) are needed. The following variables are are longer then 32 characters if two characters will be added per repeat group and should therefore be shortened:"

		noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Repeat_Group_Field_Name_Length") table("list row type name num_nested_repeats if longname2 == 1")

	}

	/***********************************************
		TEST - Name conflict after long to wide
	***********************************************/

	**List all field names and test if there is a risk that any fieldnames
	* have name conlicts when repeat field goes from long to wide and
	* number are suffixed to the end.
	qui levelsof name if will_be_field == 1 , local(listofnames) clean
	wide_name_conflicts, fieldnames("`listofnames'")

}
end

capture program drop wide_name_conflicts
	program wide_name_conflicts , rclass
qui {
		syntax , fieldnames(string)

		//Loop over all field names
		foreach field of local fieldnames {

			**The regular expression starts with the field
			* name, this is modified in each loop
			local regexpress "`field'"

			**Names are unique so this is to get the number of nested repeat
			* groups deep this field is. If it is zero the name loop below is
			* skipped as this only relates to field inside loops
			qui sum num_nested_repeats if name == "`field'"
			local numNestThisField = `r(mean)'

			**Loop over each level of nesting and add the _# regular
			* expression for each level of nesting
			forvalues nest = 1/`numNestThisField' {

				*Add one more level of _# to the regular expresison
				local regexpress "`regexpress'_[0-9]+"

				*Start the recursive regression that looks for potential conflicts
				wide_name_conflicts_rec, field("`field'") fieldnames("`fieldnames'") regexpress("`regexpress'")
			}
		}
}
end

capture program drop wide_name_conflicts_rec
	program wide_name_conflicts_rec , rclass
qui {
		syntax , field(string) fieldnames(string) regexpress(string)

		*Is there at least one match to the regular expression
		local isFieldFound 	= regexm("`fieldnames'" ," `regexpress' ")

		*If there is a match, write error and test if there are more matches
		if `isFieldFound'  == 1 {

			*Get the name of the matched field
			local fieldFound	= trim(regexs(0))

			*Display error

			local error_msg "There is a potential name conflict between field [`field'] and [`fieldFound'] as `field' is in a repeat group. When variables in repeat groups are imported to Stata they will be given the suffix `field'_1, `field'_2 etc. for each repeat in the repeat group. It is therefore bad practice to have a field name that share the name as a field in a repeat group followed by an underscore and a number, no matter how big the number is."

			noi report_file add , report_tempfile("`report_tempfile'") wikifragment("Repeat_Group_Field_Name_Length") message("`error_msg'")


			**Prepare the string to recurse on. Remove eveything up to the matched
			* field [strpos("`fieldnames'","`fieldFound'")] and the field
			* itself [strlen("`fieldFound'")] and use only everything after
			* that [substr("`fieldnames'",`stringCut', .)]
			local stringCut = strpos("`fieldnames'","`fieldFound'") + strlen("`fieldFound'")
			local newFieldnames = substr("`fieldnames'",`stringCut', .)

			*Make the recursive call
			wide_name_conflicts_rec, field("`field'") fieldnames("`newFieldnames'") regexpress("`regexpress'")
		}
}
end

capture program drop test_survey_label
		program 	 test_survey_label , rclass
qui {

		syntax , surveysheetvars(varlist) [statalanguage(string) report_tempfile(string)]

		/***********************************************
			TEST - Stata language for variable labels
			Test that there is one column with variable 
			labels formatted for stata.
		***********************************************/

		*User specified stata label name thar is not simply stata
		if "`statalanguage'" != "" {
			local labelstata "label`statalanguage'"
		}
		*Otherwise use the default name
		else {
			local labelstata "labelstata"
		}

		*Test if the Stata language column exists
		if `:list labelstata in surveysheetvars' == 0 {

			*The user specified stata label language name does not exist. Throw error
			if "`statalanguage'" != "" {
				noi di as error "{phang}The label langauge specified in {inp:statalanguage(`statalanguage')} does not exist in the survey sheet. A column in the survey sheet must have a name that is [label:`statalanguage'].{p_end}"
				noi di ""
				error 198
			}
			*The default stata label language name does not exist. Throw warning (error for now)
			else {

				local error_msg "There is no column in the survey sheet with the name [label:stata]. This is best practice as this allows you to automatically import variable labels optimized for Stata, making the data set easier to read."

				noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Stata_Labels_Columns")

			}
		}
		else {
		
		/***********************************************
			TEST - Long variable labels
			Test that variable labels are no longer than
			80 characters
		***********************************************/
		
			*Test the length of the Stata label
			gen labellength = strlen(`labelstata')

			*Names that are always too long
			gen longlabel	= (labellength > 80 & type != "note")

			*Report if a label is too long and will be truncated
			cap assert longlabel == 0
			if _rc {


				local error_msg "These stata labels are longer then 80 characters which means that Stata will cut them off. The point of having a Stata label variable is to manually make sure that the labels documenting the variables in the data set makes sense to a human reader. The following labels should be shortened:"

				noi report_file add , report_tempfile("`report_tempfile'") message("`error_msg'") wikifragment("Survey_Sheet_Stata_Labels") table("list row type name labellength `labelstata' if longlabel == 1")

			}
		}

}
end

capture program drop report_file
		program 	 report_file , rclass
qui {

		//noi di "report_file command ok"
		syntax anything , report_tempfile(string) [message(string) filepath(string) wikifragment(string) table(string) metav(string) metaid(string) metatitle(string) metafile(string)]
		//noi di "report_file syntax ok [`anything']"

		local allowed_tasks		"setup add write"

		*Get task subcommand
		gettoken task anything : anything

		*test that task is allowed
		if `:list task in allowed_tasks' == 0 {
			noi di as error "{phang}In command report_file task [`task'] is not in allowed_tasks [`allowed_tasks'].{p_end}"
			error 198
		}

		*test that only one word is used for task
		if "`anything'" != "" {
			noi di as error "{phang}In command report_file multiple words used for tasks.{p_end}"
			error 198
		}

		*No matter task you need a handler
		tempname report_handler

		*Setup files
		if "`task'" == "setup" {
		
			local user = c(username)
			local date = subinstr(c(current_date)," ","",.)

			*Write the title rows defined above
			cap file close 	`report_handler'
			file open  		`report_handler' using "`report_tempfile'", text write replace
			file write  	`report_handler' ///
				"######################################################################" _n ///
				"######################################################################" _n ///
				_n ///
				"This report was created by user `user' on `date' using the Stata command ietestform" _n ///
				_n ///
				"Use either of these links to read more about this command:" _n ///
				",https://github.com/worldbank/iefieldkit" _n ///
				",https://dimewiki.worldbank.org/wiki/Ietestform" _n ///
				_n ///
				",Form ID,`metaid'" _n ///
				",Form Title,`metatitle'" _n ///
				",Form Version,`metav'" _n ///
				",Form File,`metafile'" _n ///
				_n ///
				"######################################################################" _n ///
				"######################################################################" _n ///
				_n
			file close 		`report_handler'
		}

		*Add item to report
		else if "`task'" == "add" {

			*Add item to report
			cap file close 	`report_handler'
			file open  		`report_handler' using "`report_tempfile'", text write append
			file write  	`report_handler' ///
								"######################################################################" _n ///
								"Read more about this test and why this is an error or does not follow the best practices we recommend in https://dimewiki.worldbank.org/wiki/Ietestform#`wikifragment'" _n ///
								_n ///
								`""`message'""' _n ///
								_n ///

			file close 		`report_handler'

			if "`table'" != "" noi report_table `table' , report_tempfile("`report_tempfile'")
		}

		*Write final file to disk
		else if "`task'" == "write" {

			*Write and save report
			cap file close 	`report_handler'
			file open  		`report_handler' using "`report_tempfile'", text write append
			file write  	`report_handler' ///
				_n ///
				"######################################################################" _n ///
				"######################################################################" _n ///
				_n ///
				"This is the end of the report." _n
			file close 		`report_handler'

	

			*Write temporary file to disk
			cap copy "`report_tempfile'" "`filepath'", replace

			if _rc == 608 {
				noi di as error "{phang}The file `filepath' cannot be overwritten. If you have this file open, close it and run the command again.{p_end}"
				error 608
			}
			else if !_rc {
				noi di as result `"{phang}Report saved to: {browse "`filepath'":`filepath'} "'
			}
			else {
				*Something did not work, run the command again to get full error message and return error code
				copy "`report_tempfile'" "`filepath'", replace
			}
		}

		*Just for programming purposes, should never show
		else {
			noi di as error "Task error"
			error 198
		}


}
end


capture program drop report_table
		program 	 report_table , rclass
qui {


	//noi di "report_table command ok"
	syntax anything [if], report_tempfile(string) [options(string)]
	//noi di "report_table syntax ok [`anything']"

	preserve

		tempname report_handler

		local allowed_cmds		"list"

		*Get task subcommand
		gettoken command varlist : anything

		*test that task is allowed
		if `:list command in allowed_cmds' == 0 {
			noi di as error "{phang}In command report_file tasks [`command'] is not in allowed_tasks [`allowed_cmds'].{p_end}"
			error 198
		}

		*apply if condition if applicable
		if "`if'" != "" keep `if'

		if "`command'" == "list" {

			local rows = _N
			keep `varlist'


			*Prepare title row and name it tablestr0
			foreach var of local varlist {
				local title `"`title',"`var'" "'

				cap confirm string variable `var'
				if _rc == 0 {
					replace `var' = subinstr(`var', char(34), "", .) //remove " sign
					replace `var' = subinstr(`var', char(96), "", .) //remove ` sign
					replace `var' = subinstr(`var', char(36), "", .) //remove $ sign
					replace `var' = subinstr(`var', char(10), "", .) //remove line end
				}
			}

			*Write and save report
			cap file close 	`report_handler'
			file open  		`report_handler' using "`report_tempfile'", text write append
			file write  	`report_handler' `"`title'"' _n
			file close 		`report_handler'

			*Loop over all cases and prepare tablestrs and numbe rthem
			forvalue row = 1/`rows' {

				local row_str ""

				*loop over each var and prepare the row
				foreach var of local varlist {
					local cell_value = `var'[`row']
					local row_str `"`row_str',"`cell_value'""'
				}

				*Write and save report
				cap file close 	`report_handler'
				file open  		`report_handler' using "`report_tempfile'", text write append
				file write  	`report_handler' `"`row_str'"' _n
				file close 		`report_handler'
			}

			*Add line space
			cap file close 	`report_handler'
			file open  		`report_handler' using "`report_tempfile'", text write append
			file write  	`report_handler' _n
			file close 		`report_handler'
		}

	restore
}
end
