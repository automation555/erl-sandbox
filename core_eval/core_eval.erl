
-module(core_eval).

-compile(export_all).

-include_lib("compiler/src/core_parse.hrl").

ex() ->
    {ok, F} = file:read_file("test.core"),
    FF = binary_to_list(F),
    {ok, T, _} = core_scan:string(FF),
    core_parse:parse(T).

set_binding(Name, Value, BindingStore) ->
    orddict:store(Name, Value, BindingStore).

get_binding(Name, BindingStore) ->
    orddict:fetch(Name, BindingStore).

remove_binding(Name, BindingStore) ->
    orddict:erase(Name, BindingStore).

test() ->
    L =  {c_let,[],
	  [{c_var,[],'X1'}],
	  {c_literal,[],200},
	  {c_var,[],'X1'}},
    L2 =  {c_let,[],
	   [{c_var,[],'X1'},{c_var,[],'X2'}],
	   {c_values,[],[{c_literal,[],20},{c_literal,[],foo}]},
	   {c_tuple,[],[{c_var,[],'X1'},{c_var,[],'X2'}]}},
    L3 =  {c_call,[],
	   {c_literal,[],io},
	   {c_literal,[],format},
	   [{c_cons,[],
	     {c_literal,[],72},
	     {c_cons,[],
	      {c_literal,[],101},
	      {c_cons,[],
	       {c_literal,[],108},
	       {c_cons,[],
		{c_literal,[],108},
		{c_cons,[],
		 {c_literal,[],111},
		 {c_cons,[],
		  {c_literal,[],32},
		  {c_cons,[],
		   {c_literal,[],119},
		   {c_cons,[],
		    {c_literal,[],111},
		    {c_cons,[],
		     {c_literal,[],114},
		     {c_cons,[],
		      {c_literal,[],108},
		      {c_cons,[],
		       {c_literal,[],100},
		       {c_cons,[],
			{c_literal,[],32},
			{c_cons,[],
			 {c_literal,[],33},
			 {c_literal,[],[]}}}}}}}}}}}}}}]},

    eval(L, orddict:new()),
    eval(L2, orddict:new()),
    eval(L3, orddict:new()).
    

eval(#c_let {} = Let, BindingStore) ->
    %% compute the values of each arguments and store them in the bindingStore
    IntermediateBS =
	case Let#c_let.vars of
	    [#c_var { name = Name }] ->
		{Value, NewBindingStore} = eval(Let#c_let.arg, BindingStore),
		set_binding(Name, Value, NewBindingStore);
	    Vars ->
		%% the evaluation of the arguments should produce a list, 
		%% as it is (normaly) a c_value
		{Values, NewBindingStore} = eval(Let#c_let.arg, BindingStore),
		lists:foldl(fun({#c_var { name = Name }, Value}, FunBindingStore) ->
				    set_binding(Name, Value, FunBindingStore)
			    end, NewBindingStore, lists:zip(Vars, Values))
	end,
    %% evaluate the result
    {Result, IntermediateBS2} = eval(Let#c_let.body, IntermediateBS),
    %% Remove all binding that has been created
    FinalBinding = 
	lists:foldl(fun(#c_var { name = Name }, FoldBindingStore) ->
			    remove_binding(Name, FoldBindingStore)
		    end, IntermediateBS2, Let#c_let.vars),
    {Result, FinalBinding};

%% Litteral evaluation result as returning its value
eval(#c_literal {} = Litteral, BindingStore) ->
    {Litteral#c_literal.val, BindingStore};

%% Return the value of a variable
eval(#c_var {} = Var, BindingStore) ->
    {get_binding(Var#c_var.name, BindingStore), BindingStore};

%% Evalues all values and return a list of evaluation result for each
eval(#c_values { es = Values }, BindingStore) ->
    lists:mapfoldl(fun(Value, FunBindingStore) ->
			   eval(Value, FunBindingStore)
		   end, BindingStore, Values);

%% evaluate a tuple
eval(#c_tuple {es = Values}, BindingStore) ->
    {Result, Bindings} = 
	lists:mapfoldl(fun(Value, FunBindingStore) ->
			       eval(Value, FunBindingStore)
		       end, BindingStore, Values),
    {list_to_tuple(Result), Bindings};

%% evaluate a cons.
eval(#c_cons { hd = Head, tl = Tail}, BindingStore) ->
    %% TODO: rework this to be tail recursive
    {TailValues, TailBS} = eval(Tail, BindingStore),
    {HeadValue, HeadBS} = eval(Head, TailBS),
    {[ HeadValue | TailValues], HeadBS};


%% evaluate a function call
eval(#c_call { module = M, name = F, args = Args}, BindingStore) -> 
    {Module, ModuleBS} = eval(M, BindingStore),
    {Function, FunctionBS} = eval(F, ModuleBS),
    {RealArgs, ArgsBS} = lists:mapfoldl(fun(Arg, FunBS) ->
						eval(Arg, FunBS)
					end, FunctionBS, Args),
    {apply(Module, Function, RealArgs), ArgsBS};
    
%% evaluate a case
eval(#c_case { arg = Arg, clauses = Clauses }, BindingStore) ->
    {ArgValue, ArgBS} = eval(Arg, BindingStore),
    %% evaluate each clause until one is true
    Clause = Clauses,
    eval(Clause, ArgBS);
 
%% evaluate a clause. Return {true, NewBindingStore} or {false, BindingStore}
eval(#c_clause { pats = [Pattern | Patterns], guard = Guard, body = Body },
     BindingStore) ->
    %% test if each pattern match
    case match_patterns(Pattern, BindingStore) of
                {true, PatternsBS} ->
                    case eval_guard(Guard, PatternsBS) of
                               {true, GuardBS} ->
                                   eval(Body, GuardBS);
                               {false, GuardBS} ->
                                   {false, GuardBS}
                    end;   
                {false, PatternsBS} ->
                    {false, PatternsBS}
    end.
 
match_patterns([Pattern | Patterns], BindingStore) ->
    {Value, BS} = eval(Pattern, BindingStore),
    ok.
   
match_pattern(#c_literal {} = Litteral, BindingStore) ->
    {Litteral#c_literal.val, BindingStore}.
 
eval_guard(_Guard, BindingStore) ->
    {true, BindingStore}.
