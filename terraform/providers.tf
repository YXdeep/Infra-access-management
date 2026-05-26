---
- name: Automate Linux User Provisioning via GitOps
  hosts: all
  become: true
  vars:
    # Parses your exact Users.yaml file dynamically
    user_data: "{{ lookup('file', 'users.yaml') | from_yaml }}"

  tasks:
    - name: Ensure targeted user accounts exist or are purged
      ansible.builtin.user:
        name: "{{ item.Username }}"
        comment: "{{ item['Full name'] }} ({{ item.Email }})"
        shell: /bin/bash
        state: "{{ 'present' if item.is_currently_employed else 'absent' }}"
        remove: "{{ 'yes' if not item.is_currently_employed else 'no' }}"
      loop: "{{ user_data.Users }}"
      # Skip placeholder values if they sneak past validation
      when: item.Username != "String"

    - name: Deploy public SSH keys for active employees
      ansible.builtin.authorized_key:
        user: "{{ item.Username }}"
        state: present
        key: "{{ item.Public_Key }}"
      loop: "{{ user_data.Users }}"
      when: 
        - item.Username != "String"
        - item.is_currently_employed == true
