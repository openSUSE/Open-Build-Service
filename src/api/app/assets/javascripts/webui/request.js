function updateSupersedeAndDevelPackageDisplay() {
    if ($('#targetproject').length > 0 && $('#targetproject')[0].value.length > 0) {
        if ($('#targetproject')[0].value == $('#sourceproject')[0].value) {
            $('#sourceupdate_display').hide();
            $('#sourceupdate').prop('disabled', true); // hide 'sourceupdate' from Ruby
        } else {
            $('#sourceupdate_display').show();
            $('#sourceupdate').prop('disabled', false);
        }
        $.ajax({
            url: $('#targetproject').data('autocomplete-url'),
            data: {
                project: $('#targetproject').attr('value'),
                package: $('#package').attr('value'),
                types: 'submit',
                states: ['new', 'review', 'declined']
            },
            success: function (data) {
                if (data.indexOf('No requests') == -1) {
                    $('#supersede_display').show();
                    $('#supersede').prop('checked', true);
                    $('#pending_requests').html(data);
                } else {
                    $('#supersede_display').hide();
                    $('#supersede').prop('checked', false);
                }
            }
        });
        $.ajax({
            url: $('#targetproject').data('develpackage-url'),
            data: {
                project: $('#targetproject')[0].value,
                package: $('#package')[0].value
            },
            success: function (data) {
                if (data.length > 0) {
                    $('#devel_project_warning').show();
                    $('#devel_project_name').html(data);
                } else {
                    $('#devel_project_warning').hide();
                }
            }
        });
    }
}

function setup_request_dialog() {
    $('#devel_project_name').click(function () {
        $('#targetproject').attr('value', $('#devel_project_name').html());
    });

    $('#targetproject').autocomplete({
        source: $('#targetproject').data('autocomplete_url'),
        minLength: 2,
        select: updateSupersedeAndDevelPackageDisplay,
        change: updateSupersedeAndDevelPackageDisplay
    });

    updateSupersedeAndDevelPackageDisplay();
}

/*$("#targetpackage").autocomplete('<%= url_for :controller => :project, :action => :autocomplete_packages %>', {
 minChars: 0, matchCase: true, max: 50, extraParams: {project: function() { return $("#target_project").val(); }}
 });*/

function requestAddAcceptRequestButton() {
    $('#accept_request_button').click(function (data) {
        /* Add some hidden elements to carry HTML form data that is found at other DOM places for design reasons.  */
        if ($('.submitter_is_maintainer_checkbox').size() != 0 &&
            $('.submitter_is_maintainer_checkbox').is(':checked')) {
            additional_element = '<input id="' + $('.submitter_is_maintainer_checkbox').attr('id') +
                '" name="' + $('.submitter_is_maintainer_checkbox').attr('name') +
                '" type="hidden" value="' + $('.submitter_is_maintainer_checkbox').attr('value') + '"/>'
            $('#request_handle_form p:last').append(additional_element);
        }
        if ($('.forward_checkbox').size() != 0 &&
            $('.forward_checkbox').is(':checked')) {
            $('.forward_checkbox').each(function (index) {
                additional_element = '<input id="' + $(this).attr('id') +
                    '" name="' + $(this).attr('name') +
                    '" type="hidden" value="' + $(this).attr('value') + '"/>'
                $('#request_handle_form p:last').append(additional_element);
            });
        }
    });
}

function requestShowReview() {
    $('.review_descision_link').click(function (event) {
        $('#review_descision_select li.selected').attr('class', '');
        $(event.target).parent().attr('class', 'selected')
        $('.review_descision_display').hide();
        index = event.target.id.split('review_descision_link_')[1]
        $('#review_descision_display_' + index).show();
        return false;
    });
}

function requestAddReviewAutocomplete() {

    $('#review_type').change(function () {
        switch ($('#review_type option:selected').attr('value')) {
            case "user":
            {
                $('#review_user_span').show();
                $('#review_group_span').hide();
                $('#review_project_span').hide();
                $('#review_package_span').hide();
            }
                break;
            case "group":
            {
                $('#review_user_span').hide();
                $('#review_group_span').show();
                $('#review_project_span').hide();
                $('#review_package_span').hide();
            }
                break;
            case "project":
            {
                $('#review_user_span').hide();
                $('#review_group_span').hide();
                $('#review_project_span').show();
                $('#review_package_span').hide();
            }
                break;
            case "package":
            {
                $('#review_user_span').hide();
                $('#review_group_span').hide();
                $('#review_project_span').show();
                $('#review_package_span').show();
            }
                break;
        }
    });

    $("#review_group").autocomplete({source: '/group/autocomplete', minChars: 2, matchCase: true, max: 50});
    $("#review_user").autocomplete({source: '/user/autocomplete', minChars: 2, matchCase: true, max: 50});
    $("#review_project").autocomplete({source: '/project/autocomplete_projects', minChars: 2, matchCase: true, max: 50});
    $("#review_package").autocomplete({
        source: function (request, response) {
            $.ajax({
                url: '/project/autocomplete_packages',
                dataType: "json",
                data: {
                    term: request.term,
                    project: $("#review_project").val()
                },
                success: function (data) {
                    response(data);
                }
            });
        },
        min_length: 2,
        minChars: 0,
        matchCase: true,
        max: 50
    });
}

function setupActionLink() {
    $('.action_select_link').click(function (event) {
        $('#action_select li.selected').attr('class', '');
        $(event.target).parent().attr('class', 'selected')
        $('.action_display').hide();
        index = event.target.id.split('action_select_link_')[1]
        $('#action_display_' + index).show();
        return false;
    });
}
