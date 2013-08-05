class XpathEngine

  require 'rexml/parsers/xpathparser'

  class IllegalXpathError < APIException
    setup 400
  end

  def initialize
    @lexer = REXML::Parsers::XPathParser.new
    
    @tables = {
      'attribute' => 'attribs',
      'package' => 'packages',
      'project' => 'projects',
      'person' => 'users',
      'repository' => 'repositories',
      'issue' => 'issues',
      'request' => 'requests'
    }
    
    @attribs = {
      'packages' => {
        '@project' => {:cpart => 'projects.name',
                       joins: 'LEFT JOIN projects ON packages.db_project_id=projects.id' },
        '@name' => {:cpart => 'packages.name'},
        '@state' => {:cpart => 'issues.state', :joins => 
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issues ON issues.id = package_issues.issue_id']},
        'owner/@login' => {:cpart => 'users.login', :joins => 
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issues ON issues.id = package_issues.issue_id',
           'LEFT JOIN users ON users.id = issues.owner_id']},
        'title' => {:cpart => 'packages.title'},
        'description' => {:cpart => 'packages.description'},
        'kind' => {:cpart => 'package_kinds.kind', :joins =>
           ['LEFT JOIN package_kinds ON package_kinds.db_package_id = packages.id']},
        'devel/@project' => {:cpart => 'projs.name', :joins => 
          ['left join packages devels on packages.develpackage_id = devels.id',
           'left join projects projs on devels.db_project_id=projs.id']},
        'devel/@package' => {:cpart => 'develpackage.name', :joins => 
          ['LEFT JOIN packages develpackage ON develpackage.id = packages.develpackage_id']},
        'issue/@state' => {:cpart => 'issues.state', :joins => 
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issues ON issues.id = package_issues.issue_id',
           'LEFT JOIN attribs ON attribs.db_package_id = packages.id',
           'LEFT JOIN attrib_issues ON attrib_issues.attrib_id = attribs.id',
           'LEFT JOIN issues AS issues2 ON issues2.id = attrib_issues.issue_id',
          ]},
        'issue/@name' => {:cpart => 'issues.name = ? or issues2.name', :double => true, :joins =>
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issues ON issues.id = package_issues.issue_id',
           'LEFT JOIN attribs ON attribs.db_package_id = packages.id',
           'LEFT JOIN attrib_issues ON attrib_issues.attrib_id = attribs.id',
           'LEFT JOIN issues AS issues2 ON issues2.id = attrib_issues.issue_id',
          ]},
        'issue/@tracker' => {:cpart => 'issue_trackers.name', :joins =>
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issue_trackers ON issues.issue_tracker_id = issue_trackers.id',
           'LEFT JOIN attribs ON attribs.db_package_id = packages.id',
           'LEFT JOIN attrib_issues ON attrib_issues.attrib_id = attribs.id',
           'LEFT JOIN issue_trackers AS issue_trackers2 ON issues.issue_tracker_id = issue_trackers2.id'
          ]},
        'issue/@change' => {:cpart => 'package_issues.change',
                            joins: 'LEFT JOIN package_issues ON packages.id = package_issues.db_package_id'},
        'issue/owner/@email' => {:cpart => 'users2.email = ? or users.email', :double => 1, :joins => 
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issues ON issues.id = package_issues.issue_id',
           'LEFT JOIN users ON users.id = issues.owner_id',
           'LEFT JOIN attribs ON attribs.db_package_id = packages.id',
           'LEFT JOIN attrib_issues ON attrib_issues.attrib_id = attribs.id',
           'LEFT JOIN issues2 ON issues2.id = attrib_issues.issue_id',
           'LEFT JOIN users AS users2 ON users.id = issues2.owner_id']},
        'issue/owner/@login' => {:cpart => 'users2.login = ? or users.login', :double => 1, :joins => 
          ['LEFT JOIN package_issues ON packages.id = package_issues.db_package_id',
           'LEFT JOIN issues ON issues.id = package_issues.issue_id',
           'LEFT JOIN users ON users.id = issues.owner_id',
           'LEFT JOIN attribs ON attribs.db_package_id = packages.id',
           'LEFT JOIN attrib_issues ON attrib_issues.attrib_id = attribs.id',
           'LEFT JOIN users AS users2 ON users2.id = issues.owner_id']},
        'person/@userid' => {:cpart => 'users.login', :joins => 
          ['LEFT JOIN relationships ON packages.id = package_id',
           'LEFT JOIN users ON users.id = user_id']},
        'person/@role' => {:cpart => 'ppr.title', :joins =>
          ['LEFT JOIN relationships ON packages.id = relationships.package_id',
           'LEFT JOIN roles AS ppr ON relationships.role_id = ppr.id']},
        'group/@groupid' => {:cpart => 'groups.title', :joins =>
          ['LEFT JOIN relationships AS ppr ON packages.id = ppr.package_id',
           'LEFT JOIN groups ON groups.id = ppr.group_id']},
        'group/@role' => {:cpart => 'gpr.title', :joins =>
          ['LEFT JOIN relationships ON packages.id = relationships.package_id',
           'LEFT JOIN roles AS gpr ON relationships.role_id = gpr.id']},
        'attribute/@name' => {:cpart => 'attrib_namespaces.name = ? AND attrib_types.name',
          :split => ':', :joins => 
          ['LEFT JOIN attribs ON attribs.db_package_id = packages.id',
           'LEFT JOIN attrib_types ON attribs.attrib_type_id = attrib_types.id',
           'LEFT JOIN attrib_namespaces ON attrib_types.attrib_namespace_id = attrib_namespaces.id',
           'LEFT JOIN attribs AS attribsprj ON attribsprj.db_project_id = packages.db_project_id',   # include also, when set in project
           'LEFT JOIN attrib_types AS attrib_typesprj ON attribsprj.attrib_type_id = attrib_typesprj.id', 
           'LEFT JOIN attrib_namespaces AS attrib_namespacesprj ON attrib_typesprj.attrib_namespace_id = attrib_namespacesprj.id']},
        'project/attribute/@name' => {:cpart => 'attrib_namespaces_proj.name = ? AND attrib_types_proj.name', :split => ':', :joins =>
          ['LEFT JOIN attribs AS attribs_proj ON attribs_proj.db_project_id = packages.db_project_id',
           'LEFT JOIN attrib_types AS attrib_types_proj ON attribs_proj.attrib_type_id = attrib_types_proj.id',
           'LEFT JOIN attrib_namespaces AS attrib_namespaces_proj ON attrib_types_proj.attrib_namespace_id = attrib_namespaces_proj.id']},
      },
      'projects' => {
        '@name' => {:cpart => 'projects.name'},
        '@kind' => {:cpart => 'pt.name', :joins => [
          'LEFT JOIN db_project_types pt ON projects.type_id = pt.id']},
        'title' => {:cpart => 'projects.title'},
        'description' => {:cpart => 'projects.description'},
        'maintenance/maintains/@project' => {:cpart => 'maintained.name', :joins => [
          'LEFT JOIN projects AS maintained ON projects.id = maintained.maintenance_project_id']},
        'person/@userid' => {:cpart => 'users.login', :joins => [
          'LEFT JOIN relationships AS ppr ON projects.id = ppr.project_id',
          'LEFT JOIN users ON users.id = ppr.user_id']},
        'person/@role' => {:cpart => 'ppr.title', :joins => [
          'LEFT JOIN relationships ON projects.id = relationships.project_id',
          'LEFT JOIN roles AS ppr ON relationships.role_id = ppr.id']},
        'group/@groupid' => {:cpart => 'groups.title', :joins =>
          ['LEFT JOIN relationships gprs ON projects.id = gprs.project_id',
           'LEFT JOIN groups ON groups.id = gprs.group_id']},
        'group/@role' => {:cpart => 'gpr.title', :joins =>
          ['LEFT JOIN relationships AS gprs ON projects.id = gprs.project_id',
           'LEFT JOIN roles AS gpr ON gprs.role_id = gpr.id']},
        'repository/@name' => {:cpart => 'repositories.name'},
        'repository/path/@project' => {:cpart => 'childs.name', :joins => [
          'join repositories r on r.db_project_id=projects.id',
          'join path_elements pe on pe.parent_id=r.id',
          'join repositories r2 on r2.id=pe.repository_id',
          'join projects childs on childs.id=r2.db_project_id']},
        'repository/releasetarget/@trigger' => {:cpart => 'rt.trigger', :joins => [
          'join repositories r on r.db_project_id=projects.id',
          'join release_targets rt on rt.repository_id=r.id']},
        'package/@name' => {:cpart => 'packs.name', :joins => 
          ['LEFT JOIN packages AS packs ON packs.db_project_id = projects.id']},
        'attribute/@name' => {:cpart => 'attrib_namespaces.name = ? AND attrib_types.name', :split => ':', :joins => 
          ['LEFT JOIN attribs ON attribs.db_project_id = projects.id',
           'LEFT JOIN attrib_types ON attribs.attrib_type_id = attrib_types.id',
           'LEFT JOIN attrib_namespaces ON attrib_types.attrib_namespace_id = attrib_namespaces.id']},
      },
      'users' => {
        '@login' => {:cpart => 'users.login'},
        '@email' => {:cpart => 'users.email'},
        '@realname' => {:cpart => 'users.realname'},
        '@state' => {:cpart => 'users.state'},
       },
      'issues' => {
        '@name' => {:cpart => 'issues.name'},
        '@state' => {:cpart => 'issues.state'},
        '@tracker' => {cpart: 'issue_trackers.name',
                       joins: 'LEFT JOIN issue_trackers ON issues.issue_tracker_id = issue_trackers.id'
        },
        'owner/@email' => {:cpart => 'users.email', :joins => 
          ['LEFT JOIN users ON users.id = issues.owner_id']},
        'owner/@login' => {:cpart => 'users.login', :joins => 
          ['LEFT JOIN users ON users.id = issues.owner_id']},
      },
      'requests' => {
        '@id' => { :cpart => 'bs_requests.id' },
        'state/@name' => { :cpart => 'bs_requests.state' },
        'state/@who' => { :cpart => 'bs_requests.commenter' },
        'action/@type' => { :cpart => 'a.type',
                            joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id"
        },
        'action/grouped/@id' => { cpart: 'g.bs_request_id',
                                  joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id LEFT JOIN group_request_requests g on g.bs_request_action_group_id = a.id" },
        'action/target/@project' => { :cpart => 'a.target_project', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'action/target/@package' => { :cpart => 'a.target_package', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'action/source/@project' => { :cpart => 'a.source_project', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'action/source/@package' => { :cpart => 'a.source_package', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        # osc is doing these 4 kinds of searches during submit
        'target/@project' => { :cpart => 'a.target_project', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'target/@package' => { :cpart => 'a.target_package', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'source/@project' => { :cpart => 'a.source_project', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'source/@package' => { :cpart => 'a.source_package', joins: "LEFT JOIN bs_request_actions a ON a.bs_request_id = bs_requests.id" },
        'review/@by_user' => { :cpart => 'r.by_user', joins: "LEFT JOIN reviews r ON r.bs_request_id = bs_requests.id" },
        'review/@by_group' => { :cpart => 'r.by_group', joins: "LEFT JOIN reviews r ON r.bs_request_id = bs_requests.id" },
        'review/@by_project' => { :cpart => 'r.by_project', joins: "LEFT JOIN reviews r ON r.bs_request_id = bs_requests.id" },
        'review/@by_package' => { :cpart => 'r.by_package', joins: "LEFT JOIN reviews r ON r.bs_request_id = bs_requests.id" },
        'review/@state' => { :cpart => 'r.state', joins: "LEFT JOIN reviews r ON r.bs_request_id = bs_requests.id" },
        'history/@who' => { :cpart => 'b.commenter', joins: "LEFT JOIN bs_request_histories b on b.bs_request_id = bs_requests.id" },
        'submit/target/@project' => { empty: true },
        'submit/target/@package' => { empty: true },
        'submit/source/@project' => { empty: true },
        'submit/source/@package' => { empty: true },
      }
    }

    @operators = [:eq, :and, :or, :neq]

    @base_table = ""
    @conditions = []
    @condition_values = []
    @condition_values_needed = 1 # see xpath_func_not
    @joins = []
  end

  def logger
    Rails.logger
  end

  # Careful: there is no return value, the items found are passed to the calling block
  def find(xpath)
    #logger.debug "---------------------- parsing xpath: #{xpath} -----------------------"

    begin
      @stack = @lexer.parse xpath
    rescue NoMethodError => e
      # if the input contains a [ in random place, rexml will throw
      #  undefined method `[]' for nil:NilClass
      raise IllegalXpathError, "failed to parse #{e.inspect}"
    end
    #logger.debug "starting stack: #{@stack.inspect}"

    if @stack.shift != :document
      raise IllegalXpathError, "xpath expression has to begin with root node"
    end

    if @stack.shift != :child
      raise IllegalXpathError, "xpath expression has to begin with root node"
    end

    @stack.shift
    @stack.shift
    tablename = @stack.shift
    @base_table = @tables[tablename]
    raise IllegalXpathError, "unknown table #{tablename}" unless @base_table

    while @stack.length > 0
      token = @stack.shift
      #logger.debug "next token: #{token.inspect}"
      case token
      when :ancestor
      when :ancestor_or_self
      when :attribute
      when :descendant
      when :descendant_or_self
      when :following
      when :following_sibling
      when :namespace
      when :parent
      when :preceding
      when :preceding_sibling
      when :self
        raise IllegalXpathError, "axis '#{token}' not supported"
      when :child
        if @stack.shift != :qname
          raise IllegalXpathError, "non :qname token after :child token: #{token.inspect}"
        end
        @stack.shift #namespace
        @stack.shift #node
      when :predicate
        parse_predicate([], @stack.shift)
      else
        raise IllegalXpathError, "Unhandled token '#{token.inspect}'"
      end
    end

    #logger.debug "-------------------- end parsing xpath: #{xpath} ---------------------"

    relation = nil
    case @base_table
    when 'packages'
      relation = Package.all
    when 'projects'
      relation = Project.all
    when 'repositories'
      relation = Repository.where("db_project_id not in (?)", ProjectUserRoleRelationship.forbidden_project_ids)
    when 'requests'
      relation = BsRequest.all
    when 'users'
      relation = User.all
    when 'issues'
      relation = Issue.all
    else
      logger.debug "strange base table: #{@base_table}"
    end
    cond_ary = [@conditions.flatten.uniq.join(" AND "), @condition_values].flatten

    logger.debug("#{relation.to_sql}.find #{ { joins: @joins.flatten.uniq.join(' '),
                                               conditions: cond_ary}.inspect }")
    relation = relation.joins(@joins.flatten.uniq.join(" ")).where(cond_ary)
    relation.pluck(:id).uniq
  end

  def parse_predicate(root, stack)
    #logger.debug "------------------ predicate ---------------"
    #logger.debug "-- pred_array: #{stack.inspect} --"

    raise IllegalXpathError.new "invalid predicate" if stack.nil?

    while stack.length > 0
      token = stack.shift
      case token
      when :function
        fname = stack.shift
        fname_int = "xpath_func_"+fname.gsub(/-/, "_")
        if not respond_to? fname_int
          raise IllegalXpathError, "unknown xpath function '#{fname}'"
        end
        __send__ fname_int, root, *(stack.shift)
      when *@operators
        opname = token.to_s
        opname_int = "xpath_op_"+opname
        if not respond_to? opname_int
          raise IllegalXpathError, "unhandled xpath operator '#{opname}'"
        end
        __send__ opname_int, root, *(stack)
        stack = []
      when :child
        t = stack.shift
        if t == :qname
          stack.shift
          root << stack.shift
          t = stack.shift
          t = stack.shift
          if t == :predicate
            parse_predicate(root, stack[0])
            stack.shift
          else
            parse_predicate(root, t)
#            stack.shift
#            raise IllegalXpathError, "unhandled token in :qname '#{t.inspect}'"
          end
          root.pop
        elsif t == :any
          # noop, already shifted
        else
          raise IllegalXpathError, "unhandled token '#{t.inspect}'"
        end
      else
        raise IllegalXpathError, "illegal token X '#{token.inspect}'"
      end
    end

    #logger.debug "-------------- predicate finished ----------"
  end

  def evaluate_expr(expr, root, escape=false)
    table = @base_table
    a = Array.new
    while expr.length > 0
      token = expr.shift
      case token
      when :child
        expr.shift #qname
        expr.shift #namespace
        a << expr.shift
      when :attribute
        expr.shift #:qname token
        expr.shift #namespace
        a << "@"+expr.shift
      when :literal
        value = (escape ? escape_for_like(expr.shift) : expr.shift)
        if @last_key and @attribs[table][@last_key][:empty]
          return ""
        end
        if @last_key and @attribs[table][@last_key][:split]
          tvalues = value.split(@attribs[table][@last_key][:split])
          if tvalues.size != 2
            raise XpathEngine::IllegalXpathError, "attributes must be $NAMESPACE:$NAME"
          end
          @condition_values_needed.times { @condition_values << tvalues }
        elsif @last_key and @attribs[table][@last_key][:double]
          @condition_values_needed.times { @condition_values << [value, value] }
        else
          @condition_values_needed.times { @condition_values << value }
        end
        @last_key = nil
        return "?"
      else
        raise IllegalXpathError, "illegal token: '#{token.inspect}'"
      end
    end
    key = (root+a).join "/"
    # this is a wild hack - we need to save the key, so we can possibly split the next
    # literal. The real fix is to translate the xpath into SQL directly
    @last_key = key
    raise IllegalXpathError, "unable to evaluate '#{key}' for '#{table}'" unless @attribs[table] and @attribs[table].has_key? key
    #logger.debug "-- found key: #{key} --"
    if @attribs[table][key][:empty]
      return nil
    end
    if @attribs[table][key][:joins]
      @joins << @attribs[table][key][:joins]
    end
    if @attribs[table][key][:split]
      @split = @attribs[table][key][:split]
    end
    return @attribs[table][key][:cpart]
  end

  def escape_for_like(str)
    str.gsub(/([_%])/, '\\\\\1')
  end

  def xpath_op_eq(root, lv, rv)
    #logger.debug "-- xpath_op_eq(#{lv.inspect}, #{rv.inspect}) --"

    lval = evaluate_expr(lv, root)
    rval = evaluate_expr(rv, root)

    if lval.nil? or rval.nil?
      condition = '0'
    else
      condition = "#{lval} = #{rval}"
    end
    #logger.debug "-- condition: [#{condition}]"

    @conditions << condition
  end

  def xpath_op_neq(root, lv, rv)
    #logger.debug "-- xpath_op_neq(#{lv.inspect}, #{rv.inspect}) --"

    lval = evaluate_expr(lv, root)
    rval = evaluate_expr(rv, root)

    if lval.nil? or rval.nil?
      condition = '1'
    else
      condition = "#{lval} != #{rval}"
    end

    #logger.debug "-- condition: [#{condition}]"

    @conditions << condition
  end

  def xpath_op_and(root, lv, rv)
    #logger.debug "-- xpath_op_and(#{lv.inspect}, #{rv.inspect}) --"
    parse_predicate(root, lv)
    lv_cond = @conditions.pop
    parse_predicate(root, rv)
    rv_cond = @conditions.pop

    condition = "(#{lv_cond} AND #{rv_cond})"
    #logger.debug "-- condition: [#{condition}]"

    @conditions << condition
  end

  def xpath_op_or(root, lv, rv)
    #logger.debug "-- xpath_op_or(#{lv.inspect}, #{rv.inspect}) --"

    parse_predicate(root, lv)
    lv_cond = @conditions.pop
    parse_predicate(root, rv)
    rv_cond = @conditions.pop

    if lv_cond == '0'
      condition = rv_cond
    elsif rv_cond == '0'
      condition = lv_cond
    else
      condition = "(#{lv_cond} OR #{rv_cond})"
    end
    #logger.debug "-- condition: [#{condition}]"

    @conditions << condition
  end 

  def xpath_func_contains(root, haystack, needle)
    #logger.debug "-- xpath_func_contains(#{haystack.inspect}, #{needle.inspect}) --"

    hs = evaluate_expr(haystack, root)
    ne = evaluate_expr(needle, root, true)

    if hs.nil? or ne.nil?
      condition = '0'
    else
      condition = "LOWER(#{hs}) LIKE LOWER(CONCAT('%',#{ne},'%'))"
    end
    #logger.debug "-- condition : [#{condition}]"

    @conditions << condition
  end

  def xpath_func_not(root, expr)
    #logger.debug "-- xpath_func_not(#{expr}) --"

    # An XPath query like "not(@foo='bar')" in the SQL world means, all rows where the 'foo' column
    # is not 'bar' and where it is NULL. As a result, 'cond' below occurs twice in the resulting SQL.
    # This implies that the values to # fill those 'p.name = ?' fragments (@condition_values) have to
    # occor twice, hence the @condition_values_needed counter. For our example, the resulting SQL will
    # look like:
    #
    #   SELECT * FROM projects p LEFT JOIN db_project_types t ON p.type_id = t.id 
    #            WHERE (NOT t.name = 'maintenance_incident' OR t.name IS NULL);
    #
    # Note that this can result in bloated SQL statements, so some trust in the query optimization
    # capabilities of your DBMS is neeed :-)

    @condition_values_needed = 2
    parse_predicate(root, expr)
    cond = @conditions.pop

    condition = "(NOT #{cond} OR #{cond} IS NULL)"
    #logger.debug "-- condition : [#{condition}]"

    @condition_values_needed = 1
    @conditions << condition
  end

  def xpath_func_starts_with(root, x, y)
    #logger.debug "-- xpath_func_starts_with(#{x.inspect}, #{y.inspect}) --"

    s1 = evaluate_expr(x, root)
    s2 = evaluate_expr(y, root, true)

    condition = "#{s1} LIKE CONCAT(#{s2},'%')"
    #logger.debug "-- condition: [#{condition}]"

    @conditions << condition 
  end 

  def xpath_func_ends_with(root, x, y)
    #logger.debug "-- xpath_func_ends_with(#{x.inspect}, #{y.inspect}) --"

    s1 = evaluate_expr(x, root)
    s2 = evaluate_expr(y, root, true)

    condition = "#{s1} LIKE CONCAT('%',#{s2})"
    #logger.debug "-- condition: [#{condition}]"

    @conditions << condition 
  end 
end
