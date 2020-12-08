#pragma once

//-----------------------------------------------------------------------------
// mvTextureStorage
//
//     - This class acts as a manager for texture storage. The 
//       texture storage system serves 2 purposes:
//
//         * Allows some image based widgets to share the same textures.
//         * Allows some textures to be automatically cleaned up using
//           a reference counting system.
//
//     - AddTexture will increment an existing texture if it already exists
//     
//-----------------------------------------------------------------------------

#include <string>
#include <vector>
#include <unordered_map>

namespace Marvel {

	//-----------------------------------------------------------------------------
	// mvTexture
	//-----------------------------------------------------------------------------
	struct mvTexture
	{
		int   width = 0;
		int   height = 0;
		void* texture = nullptr;
		int   count = 0;
	};

	enum class mvTextureFormat
	{
		RGBA_INT = 0u,
		RGBA_FLOAT,
		RGB_FLOAT,
		RGB_INT
	};

	//-----------------------------------------------------------------------------
	// mvTextureStorage
	//-----------------------------------------------------------------------------
	class mvTextureStorage
	{

	public:

		void       addTexture       (const std::string& name);
		void       addTexture       (const std::string& name, float* data, unsigned width, unsigned height, mvTextureFormat format);
		void       incrementTexture (const std::string& name);
		void       decrementTexture (const std::string& name);
		mvTexture* getTexture       (const std::string& name);
		unsigned   getTextureCount  ();
		void       deleteAllTextures();

		static mvTextureStorage* GetTextureStorage();

	private:

		mvTextureStorage() = default;

		static mvTextureStorage* s_instance;
		
		std::unordered_map<std::string, mvTexture> m_textures;

	};

}