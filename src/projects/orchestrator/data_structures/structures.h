//==============================================================================
//
//  OvenMediaEngine
//
//  Created by Hyunjun Jang
//  Copyright (c) 2019 AirenSoft. All rights reserved.
//
//==============================================================================
#pragma once

#include <base/info/host.h>
#include <base/mediarouter/mediarouter_application_observer.h>

#include <regex>

#include "interfaces.h"

namespace ocst
{
	struct Module
	{
		Module(ModuleType type, const std::shared_ptr<ModuleInterface> &module);

		ModuleType type = ModuleType::Unknown;
		std::shared_ptr<ModuleInterface> module = nullptr;
	};

	struct Stream
	{
		Stream(const info::Application &app_info, const std::shared_ptr<PullProviderModuleInterface> &provider, const std::shared_ptr<pvd::Stream> &provider_stream, const ov::String &full_name);

		info::Application app_info;

		std::shared_ptr<PullProviderModuleInterface> provider;
		std::shared_ptr<pvd::Stream> provider_stream;

		ov::String full_name;

		bool is_valid = false;
	};

	struct Origin
	{
		Origin(const cfg::vhost::orgn::Origin &origin_config);

		bool IsValid() const;

		info::application_id_t app_id = 0U;

		ov::String scheme;

		// Origin/Location
		ov::String location;
		// Generated URL list from <Origin>.<Pass>.<URL>
		std::vector<ov::String> url_list;

		// Original configuration
		cfg::vhost::orgn::Origin origin_config;

		// A list of streams generated by this origin rule
		std::map<info::stream_id_t, std::shared_ptr<Stream>> stream_map;

		// A flag used to determine if an item has changed
		ItemState state = ItemState::Unknown;
	};

	struct Host
	{
		Host(const ov::String &name);

		bool IsValid() const;
		bool UpdateRegex();

		// The name of Host in the configuraiton (eg: *, *.airensoft.com)
		ov::String name;
		std::regex regex_for_domain;

		typedef std::map<info::stream_id_t, std::shared_ptr<Stream>> stream_map_t;

		// Key:
		//   1st: A host name actually used. Wildcard cannot be used
		//   2nd: A app name actually used
		// Value: A list of streams generated by this host rule
		std::map<std::pair<ov::String, ov::String>, stream_map_t> stream_map;

		// A flag used to determine if an item has changed
		ItemState state = ItemState::Unknown;
	};

	struct Application : public MediaRouteApplicationObserver
	{
		class CallbackInterface
		{
		public:
			virtual bool OnStreamCreated(const info::Application &app_info, const std::shared_ptr<info::Stream> &info) = 0;
			virtual bool OnStreamDeleted(const info::Application &app_info, const std::shared_ptr<info::Stream> &info) = 0;
			virtual bool OnStreamPrepared(const info::Application &app_info, const std::shared_ptr<info::Stream> &info) = 0;
			virtual bool OnStreamUpdated(const info::Application &app_info, const std::shared_ptr<info::Stream> &info) = 0;
		};

		Application(CallbackInterface *callback, const info::Application &app_info);

		//--------------------------------------------------------------------
		// Implementation of MediaRouteApplicationObserver
		//--------------------------------------------------------------------
		// Temporarily used until Orchestrator takes stream management
		bool OnStreamCreated(const std::shared_ptr<info::Stream> &info) override;
		bool OnStreamDeleted(const std::shared_ptr<info::Stream> &info) override;
		bool OnStreamPrepared(const std::shared_ptr<info::Stream> &info) override;
		bool OnStreamUpdated(const std::shared_ptr<info::Stream> &info) override;
		bool OnSendFrame(const std::shared_ptr<info::Stream> &info, const std::shared_ptr<MediaPacket> &packet) override;

		ObserverType GetObserverType() override;

		CallbackInterface *callback = nullptr;
		info::Application app_info;
	};

	struct VirtualHost
	{
		VirtualHost(const info::Host &host_info);

		void MarkAllAs(ItemState state);
		bool MarkAllAs(ItemState expected_old_state, ItemState state);

		// Origin Host Info
		info::Host host_info;

		// The name of VirtualHost (eg: AirenSoft-VHost)
		ov::String name;

		// Host list
		std::vector<Host> host_list;

		// Origin list
		std::vector<Origin> origin_list;

		// Application list
		std::map<info::application_id_t, std::shared_ptr<Application>> app_map;

		// A flag used to determine if an item has changed
		ItemState state = ItemState::Unknown;
	};
}  // namespace ocst
