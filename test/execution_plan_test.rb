require 'test_helper'

module Dynflow
  module ExecutionPlanTest
    describe ExecutionPlan do
      class IncommingIssues < Action

        def plan(issues)
          issues.each do |issue|
            plan_action(IncommingIssue, issue)
          end
          plan_self('issues' => issues)
        end

        input_format do
          param :issues, Array do
            param :author, String
            param :text, String
          end
        end

      end

      class IncommingIssue < Action

        def plan(issue)
          plan_self(issue)
          plan_action(Triage, issue)
        end

        input_format do
          param :author, String
          param :text, String
        end

      end

      class Triage < Action

        def plan(issue)
          triage = plan_self(issue)
          plan_action(UpdateIssue,
                      'triage_input' => triage.input,
                      'triage_output' => triage.output)
        end

        input_format do
          param :author, String
          param :text, String
        end

        output_format do
          param :assignee, String
          param :severity, %w[low medium high]
        end

        def run; end

      end

      class UpdateIssue < Action

        input_format do
          param :triage_input, Triage.input
          param :triage_output, Triage.output
        end

        def run; end
      end

      class NotifyAssignee < Action

        def self.subscribe
          Triage
        end

        input_format do
          param :triage, Triage.output
        end

        def run; end
      end

      def inspect_step(out, step, prefix)
        if step.respond_to? :steps
          out << prefix << step.class.name << "\n"
          step.steps.each { |sub_step| inspect_step(out, sub_step, prefix + "  ") }
        else
          string = step.inspect.gsub(step.action_class.name.sub(/\w+\Z/,''),'')
          out << prefix << string << "\n"
        end
      end

      def assert_run_plan(expected, execution_plan)
        plan_string = ""
        inspect_step(plan_string, execution_plan.run_plan, "")
        plan_string.chomp.must_equal expected.chomp
      end

      let :issues_data do
        [
         { 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }
        ]
      end

      let :execution_plan do
        IncommingIssues.plan(issues_data).execution_plan
      end

      it 'includes only actions with run method defined in run steps' do
        actions_with_run = [Triage,
                            UpdateIssue,
                            NotifyAssignee]
        execution_plan.run_steps.map(&:action_class).uniq.must_equal(actions_with_run)
      end

      it 'constructs the plan of actions to be executed in run phase' do
        assert_run_plan <<EXPECTED, execution_plan
Dynflow::ExecutionPlan::Concurrence
  Dynflow::ExecutionPlan::Sequence
    Triage/Run({"author"=>"Peter Smith", "text"=>"Failing test"})
    UpdateIssue/Run({"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Reference(Triage/Run({"author"=>"Peter Smith", "text"=>"Failing test"})/output)})
    NotifyAssignee/Run({"author"=>"Peter Smith", "text"=>"Failing test", "triage"=>Reference(Triage/Run({"author"=>"Peter Smith", "text"=>"Failing test"})/output)})
  Dynflow::ExecutionPlan::Sequence
    Triage/Run({"author"=>"John Doe", "text"=>"Internal server error"})
    UpdateIssue/Run({"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Reference(Triage/Run({"author"=>"John Doe", "text"=>"Internal server error"})/output)})
    NotifyAssignee/Run({"author"=>"John Doe", "text"=>"Internal server error", "triage"=>Reference(Triage/Run({"author"=>"John Doe", "text"=>"Internal server error"})/output)})
EXPECTED
      end

    end
  end
end
