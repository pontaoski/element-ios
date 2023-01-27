//
// Copyright 2021 New Vector Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Combine
import Foundation

class MXNotificationSettingsService: NotificationSettingsServiceType {
    private let session: MXSession
    private var cancellables = Set<AnyCancellable>()
    
    @Published private var contentRules = [MXPushRule]()
    @Published private var rules = [MXPushRule]()
    
    var rulesPublisher: AnyPublisher<[NotificationPushRuleType], Never> {
        $rules.map { $0.map { $0 as NotificationPushRuleType } }.eraseToAnyPublisher()
    }
    
    var contentRulesPublisher: AnyPublisher<[NotificationPushRuleType], Never> {
        $contentRules.map { $0.map { $0 as NotificationPushRuleType } }.eraseToAnyPublisher()
    }
    
    init(session: MXSession) {
        self.session = session
        // Publisher of all rule updates
        let rulesUpdated = NotificationCenter.default.publisher(for: NSNotification.Name(rawValue: kMXNotificationCenterDidUpdateRules))
        
        // Set initial value of the content rules
        if let contentRules = session.notificationCenter.rules.global.content as? [MXPushRule] {
            self.contentRules = contentRules
        }
        
        // Observe future updates to content rules
        rulesUpdated
            .compactMap { _ in self.session.notificationCenter.rules.global.content as? [MXPushRule] }
            .assign(to: &$contentRules)
        
        // Set initial value of rules
        if let flatRules = session.notificationCenter.flatRules as? [MXPushRule] {
            rules = flatRules
        }
        // Observe future updates to rules
        rulesUpdated
            .compactMap { _ in self.session.notificationCenter.flatRules as? [MXPushRule] }
            .assign(to: &$rules)
    }
    
    func add(keyword: String, enabled: Bool) {
        let index = NotificationIndex.index(when: enabled)
        guard let actions = NotificationPushRuleId.keywords.standardActions(for: index).actions else {
            return
        }
        session.notificationCenter.addContentRuleWithRuleId(matchingPattern: keyword, notify: actions.notify, sound: actions.sound, highlight: actions.highlight)
    }
    
    func remove(keyword: String) {
        guard let rule = session.notificationCenter.rule(byId: keyword) else { return }
        session.notificationCenter.removeRule(rule)
    }
    
    func updatePushRuleActions(for ruleId: String,
                               enabled: Bool,
                               actions: NotificationActions?,
                               completion: ((Result<Void, Error>) -> Void)?) {
        
        guard let rule = session.notificationCenter.rule(byId: ruleId) else {
            completion?(.success)
            return
        }
        
        guard let actions = actions else {
            enableRule(rule: rule, enabled: enabled, completion: completion)
            return
        }
        
        // Updating the actions before enabling the rule allows the homeserver to triggers just one sync update
        session.notificationCenter.updatePushRuleActions(ruleId,
                                                         kind: rule.kind,
                                                         notify: actions.notify,
                                                         soundName: actions.sound,
                                                         highlight: actions.highlight) { [weak self] error in
            switch error.result {
            case .success:
                self?.enableRule(rule: rule, enabled: enabled, completion: completion)
            case .failure:
                completion?(error.result)
            }
        }
    }
}

private extension MXNotificationSettingsService {
    func enableRule(rule: MXPushRule, enabled: Bool, completion: ((Result<Void, Error>) -> Void)?) {
        session.notificationCenter.enableRule(rule, isEnabled: enabled) { error in
            completion?(error.result)
        }
    }
}

private extension Result where Success == Void {
    static var success: Self {
        .success(())
    }
}

private extension Optional where Wrapped == Error {
    var result: Result<Void, Error> {
        map { .failure($0) } ?? .success
    }
}

