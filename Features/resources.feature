# language: en
Feature: Browse and manage Komodo resources
  As an operator of a Komodo instance
  I want dedicated server, stack, and container views
  so that I can understand and safely change my infrastructure from Varan.

  Scenario: Navigate between related resources
    Given I have selected a saved and reachable connection
    When I open a server, one of its stacks, and a container in that stack
    Then each resource has a dedicated detail view
    And I can move between the related server, stack, and container
    And the selected connection remains unchanged

  Scenario: Switch primary resource areas
    Given I have selected a saved and reachable connection
    When I use the primary navigation tabs
    Then I can switch between servers, stacks, containers, and application settings
    And each resource tab preserves its own navigation context
    And the live connection remains shared across the resource tabs

  Scenario: Inspect a server
    Given a managed server is reachable
    When I open its detail view
    Then I see its state and system information
    And I see the stacks and containers associated with it
    And unavailable information is distinguished from an empty value

  Scenario: Load related server resources
    Given I have opened a server detail view
    When its metrics, stacks, and containers are still loading
    Then loading indicators are shown instead of empty-state messages
    And section loading indicators are centered consistently
    And empty-state messages appear only after loading completes

  Scenario: Display the canonical server state
    Given a managed server summary reports its current state
    When I open its detail view
    Then the state is refreshed through the server state read API
    And missing detail metadata does not replace the state with unknown

  Scenario: Change historical metrics granularity
    Given a server history chart is visible
    When I switch between fifteen minutes, one hour, and one day
    Then Varan sends the granularity expected by Komodo
    And the history section remains visible while the new data loads
    And a failed or empty response is explained without removing the controls

  Scenario: Use consistent resource actions
    Given I am viewing a server or stack list
    Then the add action appears before the refresh action
    And a container list only offers refresh because containers belong to stacks

  Scenario: Inspect a stack container
    Given a stack contains a running container
    When I open the container detail view
    Then I see its status, image, ports, volumes, and networks
    And I can open its metrics and logs
    And runtime actions are separate from configuration editing

  Scenario: Update supported stack configuration
    Given I can write to a stack
    When I change a supported configuration field and review the changes
    Then Varan sends only the changed fields through the write API
    And further save actions are disabled while the request is in progress
    And the canonical stack is loaded again after the write succeeds

  Scenario: Update supported server configuration
    Given I can write to a server
    When I change a supported configuration field and review the changes
    Then Varan sends only the changed fields through the write API
    And the canonical server is loaded again after the write succeeds

  Scenario: Edit configuration related to a container
    Given a container is owned by a stack service
    When I choose to edit its configuration
    Then Varan opens the owning stack configuration
    And Varan does not treat the ephemeral container as an independent configuration source

  Scenario: Write permission is missing
    Given I can read a resource but cannot write to it
    When I attempt to save a change
    Then the permission failure is explained without discarding my input
    And the resource remains available in read-only form
