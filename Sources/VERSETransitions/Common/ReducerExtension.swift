//
//  ReducerExtension.swift
//  
//
//  Created by Alexander Lezya on 11.03.2022.
//

import VERSE
import os.log

extension Reducer {

    /// Transforms a reducer that works on local state, action, and environment into one that works on
    /// global state, action and environment.
    ///
    /// It accomplishes this by providing 3 transformations to the method:
    ///
    ///   * A case path that can extract/embed a piece of local state from the global state, which is
    ///     typically an enum.
    ///   * A case path that can extract/embed a local action into a global action.
    ///   * A function that can transform the global environment into a local environment.
    ///
    /// This overload of ``pullback(state:action:environment:)`` differs from the other in that it
    /// takes a `CasePath` transformation for the state instead of a `WritableKeyPath`. This makes it
    /// perfect for working on enum state as opposed to struct state. In particular, you can use this
    /// operator to pullback a reducer that operates on a single case of some state enum to work on
    /// the entire state enum.
    ///
    /// When used with the ``combine(_:)-994ak`` operator you can define many reducers that work each
    /// case of the state enum, and then _pull them back_ and _combine_ them into one big reducer that
    /// works on a large domain.
    ///
    /// ```swift
    /// // Global domain that holds a local domain:
    /// enum AppState { case loggedIn(LoggedInState), /* rest of state */ }
    /// enum AppAction { case loggedIn(LoggedInAction), /* other actions */ }
    /// struct AppEnvironment { var loggedIn: LoggedInEnvironment, /* rest of dependencies */ }
    ///
    /// // A reducer that works on the local domain:
    /// let loggedInReducer = Reducer<LoggedInState, LoggedInAction, LoggedInEnvironment> { ... }
    ///
    /// // Pullback the logged-in reducer so that it works on all of the app domain:
    /// let appReducer: Reducer<AppState, AppAction, AppEnvironment> = .combine(
    ///   loggedInReducer.pullback(
    ///     state: /AppState.loggedIn,
    ///     action: /AppAction.loggedIn,
    ///     environment: { $0.loggedIn }
    ///   ),
    ///
    ///   /* other reducers */
    /// )
    /// ```
    ///
    /// Take care when combining a child reducer for a particular case of enum state into its parent
    /// domain. A child reducer cannot process actions in its domain if it fails to extract its
    /// corresponding state. If a child action is sent to a reducer when its state is unavailable, it
    /// is generally considered a logic error, and a runtime warning will be logged. There are a few
    /// ways in which these errors can sneak into a code base:
    ///
    ///   * A parent reducer sets child state to a different case when processing a child action and
    ///     runs _before_ the child reducer:
    ///
    ///     ```swift
    ///     let parentReducer = Reducer<ParentState, ParentAction, ParentEnvironment>.combine(
    ///       // When combining reducers, the parent reducer runs first
    ///       Reducer { state, action, environment in
    ///         switch action {
    ///         case .child(.didDisappear):
    ///           // And `nil`s out child state when processing a child action
    ///           state.child = .anotherChild(AnotherChildState())
    ///           return .none
    ///         ...
    ///         }
    ///       },
    ///       // Before the child reducer runs
    ///       childReducer.pullback(state: /ParentState.child, ...)
    ///     )
    ///
    ///     let childReducer = Reducer<
    ///       ChildState, ChildAction, ChildEnvironment
    ///     > { state, action environment in
    ///       case .didDisappear:
    ///         // This action is never received here because child state cannot be extracted
    ///       ...
    ///     }
    ///     ```
    ///
    ///     To ensure that a child reducer can process any action that a parent may use to change its
    ///     state, combine it _before_ the parent:
    ///
    ///     ```swift
    ///     let parentReducer = Reducer<ParentState, ParentAction, ParentEnvironment>.combine(
    ///       // The child runs first
    ///       childReducer.pullback(state: /ParentState.child, ...),
    ///       // The parent runs after
    ///       Reducer { state, action, environment in
    ///         ...
    ///       }
    ///     )
    ///     ```
    ///
    ///   * A child effect feeds a child action back into the store when child state is unavailable:
    ///
    ///     ```swift
    ///     let childReducer = Reducer<
    ///       ChildState, ChildAction, ChildEnvironment
    ///     > { state, action environment in
    ///       switch action {
    ///       case .onAppear:
    ///         // An effect may want to later feed a result back to the child domain in an action
    ///         return environment.apiClient
    ///           .request()
    ///           .map(ChildAction.response)
    ///
    ///       case let .response(response):
    ///         // But the child cannot process this action if its state is unavailable
    ///       ...
    ///       }
    ///     }
    ///     ```
    ///
    ///     It is perfectly reasonable to ignore the result of an effect when child state is `nil`,
    ///     for example one-off effects that you don't want to cancel. However, many long-living
    ///     effects _should_ be explicitly canceled when tearing down a child domain:
    ///
    ///     ```swift
    ///     let childReducer = Reducer<
    ///       ChildState, ChildAction, ChildEnvironment
    ///     > { state, action environment in
    ///       struct MotionId: Hashable {}
    ///
    ///       switch action {
    ///       case .onAppear:
    ///         // Mark long-living effects that shouldn't outlive their domain cancellable
    ///         return environment.motionClient
    ///           .start()
    ///           .map(ChildAction.motion)
    ///           .cancellable(id: MotionId())
    ///
    ///       case .onDisappear:
    ///         // And explicitly cancel them when the domain is torn down
    ///         return .cancel(id: MotionId())
    ///       ...
    ///       }
    ///     }
    ///     ```
    ///
    ///   * A view store sends a child action when child state is `nil`:
    ///
    ///     ```swift
    ///     WithViewStore(self.parentStore) { parentViewStore in
    ///       // If child state is `nil`, it cannot process this action.
    ///       Button("Child Action") { parentViewStore.send(.child(.action)) }
    ///       ...
    ///     }
    ///     ```
    ///
    ///     Use ``Store/scope(state:action:)`` with ``SwitchStore`` to ensure that views can only send
    ///     child actions when the child domain is available.
    ///
    ///     ```swift
    ///     SwitchStore(self.parentStore) {
    ///       CaseLet(state: /ParentState.child, action: ParentAction.child) { childStore in
    ///         // This destination only appears when child state matches
    ///         WithViewStore(childStore) { childViewStore in
    ///           // So this action can only be sent when child state is available
    ///           Button("Child Action") { childViewStore.send(.action) }
    ///         }
    ///       }
    ///       ...
    ///     }
    ///     ```
    ///
    /// - See also: ``SwitchStore``, a SwiftUI helper for transforming a store on enum state into
    ///   stores on each case of the enum.
    ///
    /// - Parameters:
    ///   - toLocalState: A case path that can extract/embed `State` from `GlobalState`.
    ///   - toLocalAction: A case path that can extract/embed `Action` from `GlobalAction`.
    ///   - toLocalEnvironment: A function that transforms `GlobalEnvironment` into `Environment`.
    /// - Returns: A reducer that works on `GlobalState`, `GlobalAction`, `GlobalEnvironment`.
    public func pullback<GlobalState, GlobalAction, GlobalEnvironment>(
      state toLocalState: EnumKeyPath<GlobalState, State>,
      action toLocalAction: EnumKeyPath<GlobalAction, Action>,
      environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment,
      file: StaticString = #fileID,
      line: UInt = #line
    ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
      .init { globalState, globalAction, globalEnvironment in
        guard let localAction = toLocalAction.extract(from: globalAction) else { return .none }

        guard var localState = toLocalState.extract(from: globalState) else {
          #if DEBUG
            os_log(
              .fault, dso: rw.dso, log: rw.log,
              """
              A reducer pulled back from "%@:%d" received an action when local state was \
              unavailable. …

                Action:
                  %@

              This is generally considered an application logic error, and can happen for a few \
              reasons:

              • The reducer for a particular case of state was combined with or run from another \
              reducer that set "%@" to another case before the reducer ran. Combine or run \
              case-specific reducers before reducers that may set their state to another case. This \
              ensures that case-specific reducers can handle their actions while their state is \
              available.

              • An in-flight effect emitted this action when state was unavailable. While it may be \
              perfectly reasonable to ignore this action, you may want to cancel the associated \
              effect before state is set to another case, especially if it is a long-living effect.

              • This action was sent to the store while state was another case. Make sure that \
              actions for this reducer can only be sent to a view store when state is non-"nil". \
              In SwiftUI applications, use "SwitchStore".
              """,
              "\(file)",
              line,
              debugCaseOutput(localAction),
              "\(State.self)"
            )
          #endif
          return .none
        }
        defer { globalState = toLocalState.embed(localState) }

        let effects = self.run(
          &localState,
          localAction,
          toLocalEnvironment(globalEnvironment)
        )
        .map(toLocalAction.embed)

        return effects
      }
    }
}

func debugCaseOutput(_ value: Any) -> String {
    func debugCaseOutputHelp(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .enum:
            guard let child = mirror.children.first else {
                let childOutput = "\(value)"
                return childOutput == "\(type(of: value))" ? "" : ".\(childOutput)"
            }
            let childOutput = debugCaseOutputHelp(child.value)
            return ".\(child.label ?? "")\(childOutput.isEmpty ? "" : "(\(childOutput))")"
        case .tuple:
            return mirror.children.map { label, value in
                let childOutput = debugCaseOutputHelp(value)
                return "\(label.map { isUnlabeledArgument($0) ? "_:" : "\($0):" } ?? "")\(childOutput.isEmpty ? "" : " \(childOutput)")"
            }
            .joined(separator: ", ")
        default:
            return ""
        }
    }

    return "\(type(of: value))\(debugCaseOutputHelp(value))"
}

private func isUnlabeledArgument(_ label: String) -> Bool {
    label.firstIndex(where: { $0 != "." && !$0.isNumber }) == nil
}
